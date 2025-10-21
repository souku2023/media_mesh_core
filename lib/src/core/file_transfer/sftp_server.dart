part of '../../media_mesh_core_base.dart';

/// A simplified SFTP client wrapper that can connect to external SFTP servers
/// and restrict access to specific paths.
///
/// Note: The dartssh2 package is primarily designed for SSH client functionality.
/// For full SFTP server functionality, consider using a different package or
/// implementing server functionality using lower-level networking libraries.
class MediaMeshSftpServer {
  /// The paths the SFTP client is allowed to access when connecting to external servers
  final List<Directory> allowedPaths;
  final String host;
  final int port;
  final String username;
  final String password;

  MediaMeshSftpServer({
    required this.host,
    required this.port,
    required this.username,
    required this.password,
    required this.allowedPaths,
  });
}
