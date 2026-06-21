# macOS App Permissions and TCC Audit Toolkit

This toolkit audits macOS application permission records and provides a supported reset workflow for individual applications.

## Audit

```bash
chmod +x src/tcc_permissions_audit.sh
sudo ./src/tcc_permissions_audit.sh
```

The audit reports database availability, permission records when accessible, application bundle identifiers and recent permission-service events.

## Repair

Preview a camera permission reset:

```bash
chmod +x src/tcc_permissions_repair.sh
./src/tcc_permissions_repair.sh --reset Camera --bundle-id us.zoom.xos --dry-run
```

Reset a microphone permission:

```bash
./src/tcc_permissions_repair.sh --reset Microphone --bundle-id com.microsoft.teams2
```

Reset all resettable decisions for one app:

```bash
./src/tcc_permissions_repair.sh --reset-all --bundle-id com.example.app
```

## Repair behaviour

- Uses the built-in `tccutil reset` command.
- Targets a specific service and application bundle ID unless `--reset-all` is selected.
- Refreshes the user permission service after the reset.
- Supports confirmation, dry-run, logs and verification output.
- Does not edit the permission databases directly.
- Does not approve access automatically; the application must request access again.

Some permission types still require manual approval in System Settings. Full Disk Access may be required to read all audit data.

## Author

Dewald Pretorius — L2 IT Support Engineer
