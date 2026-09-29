//! MobileBackup2 FFI — Real device backup/restore via mobilebackup2 protocol.
//!
//! This implements the genuine GoldenNugget-mobile backup method:
//! - Backup: pull device backup via mobilebackup2 → local directory
//! - Restore: push modified backup back via mobilebackup2
//!
//! Uses the idevice crate's mobilebackup2 client over the loopback tunnel
//! (same tunnel infrastructure as the AirLift exploit).

use std::ffi::{CStr, CString, c_char, c_void};
use std::path::{Path, PathBuf};
use std::pin::Pin;
use std::future::Future;
use std::io::{Read, Write};

use idevice::services::mobilebackup2::{BackupDelegate, FsBackupDelegate, MobileBackup2Client};
use idevice::{Idevice, IdeviceError};

use crate::exploit::{ALLogCallback, AppDeviceTunnel, Logger, connect_service_lockdown, connect_tunnel, stage_err};
use crate::ffi_util;

// ---------------------------------------------------------------------------
// Progress callback
// ---------------------------------------------------------------------------

/// Progress callback: called with percent (0-100) and a status message.
pub type MBProgressCallback = Option<extern "C" fn(ctx: *mut c_void, percent: f64, message: *const c_char)>;

struct ProgressReporter {
    cb: MBProgressCallback,
    ctx: *mut c_void,
}

impl ProgressReporter {
    fn report(&self, percent: f64, message: &str) {
        if let Some(cb) = self.cb {
            if let Ok(c) = CString::new(message) {
                cb(self.ctx, percent, c.as_ptr());
            }
        }
    }
}

// ---------------------------------------------------------------------------
// Backup/Restore implementation
// ---------------------------------------------------------------------------

/// Connect to mobilebackup2 service via the tunnel.
async fn connect_mobilebackup2(
    pairing_bytes: &[u8],
    logger: &Logger,
) -> Result<MobileBackup2Client, String> {
    let tunnel = connect_tunnel(pairing_bytes, logger).await?;
    
    let stream: Box<dyn idevice::ReadWrite> = match tunnel {
        AppDeviceTunnel::Rsd { adapter, mut handshake } => {
            logger.log("mb2: connecting via RSD tunnel...");
            // For RSD, we need to use the handshake to start the service
            // This is a simplified path - full implementation would use RSD service start
            return Err(stage_err("tunnel", "RSD tunnel mobilebackup2 not yet implemented - use lockdown pairing"));
        }
        AppDeviceTunnel::Lockdown { provider, pairing_file, legacy } => {
            connect_service_lockdown(&provider, &pairing_file, legacy, "com.apple.mobilebackup2", logger).await?
        }
    };
    
    let idevice = Idevice::new(stream, "WorkSlop-MB2");
    Ok(MobileBackup2Client::new(idevice))
}

/// Pull a device backup via mobilebackup2.
/// 
/// - `pairing_path`: path to the pairing file
/// - `udid`: device UDID (source identifier)
/// - `backup_root`: directory where backup will be stored (<backup_root>/<udid>/)
/// - Returns 0 on success, non-zero on failure
async fn mb2_backup_impl(
    pairing_path: &str,
    udid: &str,
    backup_root: &str,
    logger: &Logger,
    progress: &ProgressReporter,
) -> Result<(), String> {
    logger.log("mb2: reading pairing file...");
    let pairing_bytes = std::fs::read(pairing_path)
        .map_err(|e| stage_err("pairing", format!("failed to read pairing file: {e}")))?;
    
    progress.report(5.0, "Connecting to device...");
    let mut client = connect_mobilebackup2(&pairing_bytes, logger).await?;
    
    progress.report(10.0, "Starting backup...");
    logger.log("mb2: starting backup...");
    
    let backup_path = Path::new(backup_root);
    let delegate = FsBackupDelegate::new();
    
    // Start the backup with default options
    // Note: GoldenNugget-mobile uses skipAppContainers=true for protective backup
    let options = None; // Use defaults
    
    progress.report(15.0, "Pulling backup data...");
    client.backup_from_path(backup_path, Some(udid), options, &delegate)
        .await
        .map_err(|e| stage_err("backup", format!("backup failed: {e:?}")))?;
    
    progress.report(100.0, "Backup complete");
    logger.log("mb2: backup complete");
    Ok(())
}

/// Restore a device backup via mobilebackup2.
/// 
/// - `pairing_path`: path to the pairing file
/// - `udid`: device UDID (source identifier)  
/// - `backup_root`: directory containing the backup (<backup_root>/<udid>/)
/// - Returns 0 on success, non-zero on failure
async fn mb2_restore_impl(
    pairing_path: &str,
    udid: &str,
    backup_root: &str,
    logger: &Logger,
    progress: &ProgressReporter,
) -> Result<(), String> {
    logger.log("mb2: reading pairing file...");
    let pairing_bytes = std::fs::read(pairing_path)
        .map_err(|e| stage_err("pairing", format!("failed to read pairing file: {e}")))?;
    
    progress.report(5.0, "Connecting to device...");
    let mut client = connect_mobilebackup2(&pairing_bytes, logger).await?;
    
    progress.report(10.0, "Starting restore...");
    logger.log("mb2: starting restore...");
    
    let backup_path = Path::new(backup_root);
    let delegate = FsBackupDelegate::new();
    
    // Restore options: don't reboot automatically (user reboots manually)
    let options = idevice::mobilebackup2::RestoreOptions::new()
        .with_reboot(false)
        .with_preserve_settings(true);
    
    progress.report(15.0, "Pushing backup data...");
    client.restore_from_path(backup_path, Some(udid), Some(options), &delegate)
        .await
        .map_err(|e| stage_err("restore", format!("restore failed: {e:?}")))?;
    
    progress.report(100.0, "Restore complete");
    logger.log("mb2: restore complete");
    Ok(())
}

// ---------------------------------------------------------------------------
// FFI entry points
// ---------------------------------------------------------------------------

fn run_mb2_op(
    pairing_path: *const c_char,
    udid: *const c_char,
    backup_root: *const c_char,
    log_cb: ALLogCallback,
    progress_cb: MBProgressCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
    is_backup: bool,
) -> i32 {
    // Safety: validated by caller
    let pairing_path = unsafe {
        if pairing_path.is_null() {
            if !out_error.is_null() {
                unsafe { *out_error = ffi_util::cstr("pairing_path is null".to_string()); }
            }
            return 1;
        }
        match CStr::from_ptr(pairing_path).to_str() {
            Ok(s) => s,
            Err(_) => {
                if !out_error.is_null() {
                    unsafe { *out_error = ffi_util::cstr("pairing_path is not valid UTF-8".to_string()); }
                }
                return 1;
            }
        }
    };
    
    let udid = unsafe {
        if udid.is_null() {
            if !out_error.is_null() {
                unsafe { *out_error = ffi_util::cstr("udid is null".to_string()); }
            }
            return 1;
        }
        match CStr::from_ptr(udid).to_str() {
            Ok(s) => s,
            Err(_) => {
                if !out_error.is_null() {
                    unsafe { *out_error = ffi_util::cstr("udid is not valid UTF-8".to_string()); }
                }
                return 1;
            }
        }
    };
    
    let backup_root = unsafe {
        if backup_root.is_null() {
            if !out_error.is_null() {
                unsafe { *out_error = ffi_util::cstr("backup_root is null".to_string()); }
            }
            return 1;
        }
        match CStr::from_ptr(backup_root).to_str() {
            Ok(s) => s,
            Err(_) => {
                if !out_error.is_null() {
                    unsafe { *out_error = ffi_util::cstr("backup_root is not valid UTF-8".to_string()); }
                }
                return 1;
            }
        }
    };
    
    let logger = Logger { cb: log_cb, ctx };
    let progress = ProgressReporter { cb: progress_cb, ctx };
    
    let result = crate::ffi_util::run_with_large_stack(
        if is_backup { "mb2_backup" } else { "mb2_restore" },
        move || {
            if is_backup {
                mb2_backup_impl(pairing_path, udid, backup_root, &logger, &progress)
            } else {
                mb2_restore_impl(pairing_path, udid, backup_root, &logger, &progress)
            }
        },
    );
    
    match result {
        Ok(Ok(())) => 0,
        Ok(Err(e)) => {
            if !out_error.is_null() {
                unsafe { *out_error = ffi_util::cstr(e); }
            }
            1
        }
        Err(e) => {
            if !out_error.is_null() {
                unsafe { *out_error = ffi_util::cstr(format!("Rust panic: {e:?}")); }
            }
            1
        }
    }
}

/// Pull a device backup via mobilebackup2.
///
/// # Safety
/// All pointer arguments must be null or valid for their documented use.
#[no_mangle]
pub unsafe extern "C" fn mb2_backup(
    pairing_path: *const c_char,
    udid: *const c_char,
    backup_root: *const c_char,
    log_cb: ALLogCallback,
    progress_cb: MBProgressCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> i32 {
    run_mb2_op(pairing_path, udid, backup_root, log_cb, progress_cb, ctx, out_error, true)
}

/// Restore a device backup via mobilebackup2.
///
/// # Safety
/// All pointer arguments must be null or valid for their documented use.
#[no_mangle]
pub unsafe extern "C" fn mb2_restore(
    pairing_path: *const c_char,
    udid: *const c_char,
    backup_root: *const c_char,
    log_cb: ALLogCallback,
    progress_cb: MBProgressCallback,
    ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> i32 {
    run_mb2_op(pairing_path, udid, backup_root, log_cb, progress_cb, ctx, out_error, false)
}
