import '../../account_backup/data/backup_api_client.dart';

class SyncApiClient extends BackupApiClient {
  SyncApiClient({required super.auth, super.baseUrl, super.client})
    : super(apiPath: 'sync', requestTimeout: const Duration(seconds: 30));
}
