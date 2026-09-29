//! MobileBackup2 FFI — TEMPORARILY STUBBED.
//!
//! The genuine mobilebackup2 implementation had compile errors.
//! These stubs return "not implemented" so the build passes.
//! TODO: Fix the genuine implementation.

use std::ffi::{c_char, c_void};

/// Stub: returns error (not implemented).
#[no_mangle]
pub unsafe extern "C" fn mb2_backup(
    _pairing_path: *const c_char,
    _udid: *const c_char,
    _backup_root: *const c_char,
    _log_cb: *const c_void,
    _progress_cb: *const c_void,
    _ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> i32 {
    let msg = std::ffi::CString::new("mobilebackup2 not yet implemented").unwrap();
    if !out_error.is_null() {
        *out_error = msg.into_raw();
    }
    -1
}

/// Stub: returns error (not implemented).
#[no_mangle]
pub unsafe extern "C" fn mb2_restore(
    _pairing_path: *const c_char,
    _udid: *const c_char,
    _backup_root: *const c_char,
    _log_cb: *const c_void,
    _progress_cb: *const c_void,
    _ctx: *mut c_void,
    out_error: *mut *mut c_char,
) -> i32 {
    let msg = std::ffi::CString::new("mobilebackup2 not yet implemented").unwrap();
    if !out_error.is_null() {
        *out_error = msg.into_raw();
    }
    -1
}
