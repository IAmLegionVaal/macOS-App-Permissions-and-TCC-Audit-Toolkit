# macOS App Permissions and TCC Audit Toolkit

A read-only Bash toolkit for auditing macOS privacy-permission indicators for camera, microphone, screen recording, accessibility, automation, location, and Full Disk Access.

## Usage

```bash
chmod +x src/tcc_permissions_audit.sh
sudo ./src/tcc_permissions_audit.sh
```

## Checks performed

- User and system TCC database availability
- Privacy-service authorization records when database access is permitted
- Applications referenced by camera, microphone, screen capture, accessibility, Apple Events, location, and system-policy services
- TCC database ownership, permissions, and modification times
- Recent `tccd` and privacy-permission events
- Text, CSV, and JSON reports

## Access requirements

Reading the system or user TCC databases may require Full Disk Access. The script handles inaccessible databases without attempting to bypass macOS privacy protections.

## Safety

The toolkit never grants, revokes, resets, or modifies privacy permissions and does not run `tccutil reset`.

## Privacy

Reports can contain application bundle identifiers and permission decisions. Review them before sharing.

## Author

Dewald Pretorius — L2 IT Support Engineer
