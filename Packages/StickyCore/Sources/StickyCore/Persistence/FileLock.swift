import Darwin
import Foundation

/// Advisory, cross-process exclusive lock using `flock(2)` on a dedicated lock file.
///
/// A separate lock file is required because the data file is replaced atomically
/// (rename), which would orphan a lock held on the old inode.
/// `flock` locks belong to the open file description, so two `FileLock`s in the same
/// process also exclude each other.
final class FileLock {
    private var fd: Int32

    private init(fd: Int32) { self.fd = fd }

    /// Acquires the lock, polling without blocking a thread, up to `timeout`.
    static func acquire(at url: URL, timeout: Duration = .seconds(5)) async throws -> FileLock {
        let fd = open(url.path, O_RDWR | O_CREAT | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw RepositoryError.lockFailed(errno: errno) }

        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while true {
            if flock(fd, LOCK_EX | LOCK_NB) == 0 {
                return FileLock(fd: fd)
            }
            let err = errno
            guard err == EWOULDBLOCK || err == EINTR else {
                close(fd)
                throw RepositoryError.lockFailed(errno: err)
            }
            if clock.now >= deadline {
                close(fd)
                throw RepositoryError.lockTimeout
            }
            do {
                try await Task.sleep(for: .milliseconds(5))
            } catch {
                close(fd)
                throw error
            }
        }
    }

    /// Releases the lock. Safe to call more than once.
    func unlock() {
        guard fd >= 0 else { return }
        flock(fd, LOCK_UN)
        close(fd)
        fd = -1
    }

    deinit { unlock() }
}
