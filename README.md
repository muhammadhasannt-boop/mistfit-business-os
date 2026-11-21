# MISTFIT Business OS V1

Android-first, offline-first Flutter starter project.

## Included in V1
- Local SQLite database
- Product create/edit/delete
- Product variants as size and color fields
- Stock quantity tracking
- Sale recording with automatic stock deduction
- Expense recording and categories
- Dashboard: revenue, gross product profit, recorded expenses, net estimate
- Basic offline rule-based alerts

## Important accounting note
The displayed net figure is gross product profit minus recorded expenses. It is not a complete accounting statement until all costs, returns, taxes, discounts, fees and stock adjustments are implemented.

## Build APK using GitHub Actions from an Android phone
1. Create a GitHub account or sign in.
2. Create a new repository named `mistfit-business-os`.
3. Upload all files and folders from this project ZIP to the repository root (including the hidden `.github` folder).
4. Open the repository's Actions tab.
5. Select `Build MISTFIT Android APK` and tap `Run workflow`.
6. When the run completes, open it and download the `mistfit-business-os-apk` artifact.
7. Extract the artifact ZIP; install `app-release.apk` on your Android phone.

The first build requires internet. Once installed, core data entry and analysis work offline.

## Development status
This is a starter MVP source project, not a prebuilt or tested APK. The GitHub Actions build runs Flutter analysis and produces a release APK; resolve any build/analyzer issue reported by the workflow before installing. Test with sample records before entering real business data. Backups, authentication, audit history, supplier/customer modules, returns, taxes, multi-user sync and advanced analytics are future work.
