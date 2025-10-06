# Apple-Speech-App

Starter App and Reference for Apple Speech implementation

## MEGA integration

The application now supports offloading recordings to [MEGA](https://mega.io/).
Provide the following keys in your app's `Info.plist` before building:

| Key | Description |
| --- | --- |
| `MEGAAppKey` | MEGA SDK app key. |
| `MEGAUserAgent` | Custom user agent string used by the SDK. |
| `MEGAEmail` | Account email used for authentication. |
| `MEGAPassword` | Account password. |
| `MEGAParentHandle` (optional) | Numeric node handle for the destination folder. If omitted, uploads go to the account root. |

These values are read at runtime by `MegaStorageService`. Ensure the credentials are
stored securely for production use.
