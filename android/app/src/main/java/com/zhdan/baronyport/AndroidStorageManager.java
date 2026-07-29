package com.zhdan.baronyport;

import android.app.Activity;
import android.app.AlertDialog;
import android.content.ContentResolver;
import android.content.Intent;
import android.net.Uri;
import android.provider.OpenableColumns;
import android.util.Log;

import org.json.JSONException;
import org.json.JSONObject;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;
import java.time.ZoneOffset;
import java.time.format.DateTimeFormatter;
import java.util.Arrays;
import java.util.Collections;
import java.util.HashSet;
import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;
import java.util.zip.ZipOutputStream;

final class AndroidStorageManager {
    static final String DATA_IMPORT_DIRECTORY = "barony-data-import";

    private static final String TAG = "BaronyAndroid";
    private static final int REQUEST_IMPORT_DATA = 7310;
    private static final int REQUEST_EXPORT_STATE = 7311;
    private static final int REQUEST_IMPORT_STATE = 7312;
    private static final String DATA_IMPORT_READY = ".barony-import-ready";
    private static final String DATA_MANIFEST_NAME = ".barony-android-data.json";
    private static final String STATE_MANIFEST_NAME = "manifest.json";
    private static final String STATE_PAYLOAD_DIRECTORY = "payload";
    private static final int STATE_MANIFEST_SCHEMA = 1;
    private static final int DATA_ARCHIVE_MAX_FILES = 100_000;
    private static final long DATA_ARCHIVE_MAX_BYTES = 2L * 1024L * 1024L * 1024L;
    private static final long DATA_ARCHIVE_MAX_ENTRY_BYTES = 256L * 1024L * 1024L;
    private static final long ARCHIVE_MANIFEST_MAX_BYTES = 1024L * 1024L;
    private static final int STATE_ARCHIVE_MAX_FILES = 512;
    private static final long STATE_ARCHIVE_MAX_BYTES = 64L * 1024L * 1024L;
    private static final int COPY_BUFFER_SIZE = 128 * 1024;
    private static final DateTimeFormatter ARCHIVE_TIME =
            DateTimeFormatter.ofPattern("yyyyMMdd-HHmmss", Locale.ROOT)
                    .withZone(ZoneOffset.UTC);

    private static final Set<String> DATA_DIRECTORIES =
            Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
                    "books", "data", "fonts", "images", "items", "lang", "maps",
                    "models", "music", "sound")));
    private static final Set<String> DATA_ROOT_FILES =
            Collections.unmodifiableSet(new HashSet<>(Arrays.asList(
                    "gamecontrollerdb.txt",
                    "npcnames-female.txt",
                    "npcnames-male.txt",
                    "playernames-female.txt",
                    "playernames-male.txt",
                    "dlc.unlock",
                    "mythsandoutcasts.key",
                    "legendsandpariahs.key",
                    "desertersanddisciples.key",
                    DATA_MANIFEST_NAME)));

    private final BaronyActivity host;
    private final ExecutorService executor = Executors.newSingleThreadExecutor();
    private AlertDialog operationDialog;
    private boolean pickerOpenedWhileBlocked;
    private boolean shuttingDown;

    AndroidStorageManager(BaronyActivity host) {
        this.host = host;
    }

    void show() {
        if (shuttingDown || host.isFinishing() || host.isDestroyed()) {
            return;
        }
        String[] actions = {
                "Import owned game data",
                "Export saves and settings",
                "Import saves and settings"
        };
        new AlertDialog.Builder(host)
                .setTitle("Barony data and saves")
                .setItems(actions, (dialog, which) -> {
                    if (which == 0) {
                        pickOwnedDataArchive();
                    } else if (which == 1) {
                        createStateArchive();
                    } else if (which == 2) {
                        pickStateArchive();
                    }
                })
                .setNegativeButton("Cancel", null)
                .show();
    }

    void pickOwnedDataArchive() {
        pickerOpenedWhileBlocked = host.isNativeStartupBlocked();
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/octet-stream"
                });
        host.startActivityForResult(intent, REQUEST_IMPORT_DATA);
        Log.i(TAG, "BARONY_ANDROID_DATA_ARCHIVE_PICKER_OPENED");
    }

    private void pickStateArchive() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("*/*")
                .putExtra(Intent.EXTRA_MIME_TYPES, new String[] {
                        "application/zip",
                        "application/x-zip-compressed",
                        "application/octet-stream"
                });
        host.startActivityForResult(intent, REQUEST_IMPORT_STATE);
        Log.i(TAG, "BARONY_ANDROID_STATE_ARCHIVE_IMPORT_PICKER_OPENED");
    }

    private void createStateArchive() {
        String filename = "Barony-Android-Saves-"
                + ARCHIVE_TIME.format(Instant.now()) + ".zip";
        Intent intent = new Intent(Intent.ACTION_CREATE_DOCUMENT)
                .addCategory(Intent.CATEGORY_OPENABLE)
                .setType("application/zip")
                .putExtra(Intent.EXTRA_TITLE, filename);
        host.startActivityForResult(intent, REQUEST_EXPORT_STATE);
        Log.i(TAG, "BARONY_ANDROID_STATE_ARCHIVE_EXPORT_PICKER_OPENED");
    }

    boolean handleActivityResult(int requestCode, int resultCode, Intent data) {
        if (requestCode != REQUEST_IMPORT_DATA
                && requestCode != REQUEST_EXPORT_STATE
                && requestCode != REQUEST_IMPORT_STATE) {
            return false;
        }

        if (resultCode != Activity.RESULT_OK || data == null || data.getData() == null) {
            if (requestCode == REQUEST_IMPORT_DATA && pickerOpenedWhileBlocked) {
                host.showCurrentDataRequirement();
            }
            return true;
        }

        Uri uri = data.getData();
        if (requestCode == REQUEST_IMPORT_DATA) {
            runTask(
                    "Importing Barony game data",
                    "Validating and extracting the owned-data archive…",
                    () -> importOwnedData(uri));
        } else if (requestCode == REQUEST_EXPORT_STATE) {
            runTask(
                    "Exporting saves and settings",
                    "Creating the portable save archive…",
                    () -> exportState(uri));
        } else {
            runTask(
                    "Importing saves and settings",
                    "Validating the portable save archive…",
                    () -> importState(uri));
        }
        return true;
    }

    BaronyActivity.DataValidation applyPendingDataImportAtStartup() {
        File staging = host.getBaronyDataImportDirectory();
        if (staging == null || !staging.exists()) {
            return BaronyActivity.DataValidation.success();
        }

        File ready = new File(staging, DATA_IMPORT_READY);
        if (!ready.isFile()) {
            deleteRecursively(staging);
            Log.w(TAG, "BARONY_ANDROID_DATA_ARCHIVE_PARTIAL_REMOVED");
            return BaronyActivity.DataValidation.success();
        }

        BaronyActivity.DataValidation validation =
                host.validateGameData(staging, "android-document-import");
        if (!validation.valid) {
            Log.e(TAG, "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_FAILED stage=pending_validation"
                    + " detail=" + validation.detail);
            return validation;
        }

        if (!ready.delete()) {
            return BaronyActivity.DataValidation.failure(
                    "import_apply_failed",
                    "The validated import could not be finalized.");
        }

        try {
            File destination = host.getBaronyDataDirectory();
            File backup = promoteDirectory(
                    staging, destination, "barony-data-backup");
            BaronyActivity.DataValidation installed =
                    host.validateGameData(
                            destination, "android-document-import");
            if (!installed.valid) {
                try {
                    rollbackPromotedDirectory(destination, backup);
                } catch (IOException rollbackError) {
                    Log.e(TAG,
                            "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_FAILED stage=rollback",
                            rollbackError);
                    return BaronyActivity.DataValidation.failure(
                            "import_rollback_failed",
                            installed.detail
                                    + " The previous data also could not be restored: "
                                    + rollbackError.getMessage());
                }
                return installed;
            }
            removeCompletedBackup(backup);
            Log.i(TAG, "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_APPLIED");
            return BaronyActivity.DataValidation.success();
        } catch (IOException error) {
            Log.e(TAG, "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_FAILED stage=apply", error);
            return BaronyActivity.DataValidation.failure(
                    "import_apply_failed",
                    "The validated archive could not replace the existing game data: "
                            + error.getMessage());
        }
    }

    private TaskResult importOwnedData(Uri uri) throws IOException {
        File staging = host.getBaronyDataImportDirectory();
        if (staging == null) {
            return TaskResult.failure(
                    "Import unavailable",
                    "App-specific external storage is unavailable on this device.");
        }

        prepareEmptyDirectory(staging);
        Log.i(TAG, "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_STARTED");
        ExtractionStats stats;
        try {
            stats = extractArchive(
                    uri,
                    staging,
                    DATA_ARCHIVE_MAX_FILES,
                    DATA_ARCHIVE_MAX_BYTES,
                    true);
            BaronyActivity.DataValidation validation =
                    host.validateGameData(staging, "android-document-import");
            if (!validation.valid) {
                deleteRecursively(staging);
                return TaskResult.failure("Game data import failed", validation.detail);
            }
            Files.write(
                    new File(staging, DATA_IMPORT_READY).toPath(),
                    "ready\n".getBytes(StandardCharsets.UTF_8));
        } catch (IOException error) {
            deleteRecursively(staging);
            throw error;
        }

        Log.i(TAG, "BARONY_ANDROID_DATA_ARCHIVE_IMPORT_READY files="
                + stats.files + " bytes=" + stats.bytes);
        if (host.isNativeStartupBlocked()) {
            BaronyActivity.DataValidation applied = applyPendingDataImportAtStartup();
            if (!applied.valid) {
                return TaskResult.failure("Game data import failed", applied.detail);
            }
            return TaskResult.dataApplied(
                    "Game data imported",
                    "The owned Barony data was validated and installed successfully.");
        }

        return TaskResult.restart(
                "Game data ready",
                "The owned Barony data was validated. Exit now, then open the port "
                        + "again to apply it.");
    }

    private TaskResult exportState(Uri uri)
            throws IOException, JSONException, NoSuchAlgorithmException {
        LinkedHashMap<String, File> files = new LinkedHashMap<>();
        collectStateFiles(
                host.getBaronyOutputDirectory(),
                new File(host.getBaronyOutputDirectory(), "savegames"),
                files);
        collectStateFiles(
                host.getBaronyOutputDirectory(),
                new File(host.getBaronyOutputDirectory(), "config"),
                files);
        if (files.isEmpty()) {
            return TaskResult.failure(
                    "Nothing to export",
                    "No Barony saves or settings exist yet.");
        }
        if (files.size() > STATE_ARCHIVE_MAX_FILES) {
            return TaskResult.failure(
                    "Too many files",
                    "The save/settings export exceeds "
                            + STATE_ARCHIVE_MAX_FILES + " files.");
        }

        long expectedBytes = 0L;
        for (Map.Entry<String, File> entry : files.entrySet()) {
            expectedBytes += entry.getValue().length();
            if (expectedBytes > STATE_ARCHIVE_MAX_BYTES) {
                return TaskResult.failure(
                        "Export too large",
                        "The save/settings export exceeds 64 MiB.");
            }
        }

        ContentResolver resolver = host.getContentResolver();
        long archivedBytes = 0L;
        try (OutputStream raw = resolver.openOutputStream(uri, "w")) {
            if (raw == null) {
                throw new IOException("The selected document could not be opened.");
            }
            try (ZipOutputStream zip = new ZipOutputStream(new BufferedOutputStream(raw))) {
                JSONObject hashes = new JSONObject();
                byte[] buffer = new byte[COPY_BUFFER_SIZE];
                int completed = 0;
                for (Map.Entry<String, File> entry : files.entrySet()) {
                    ZipEntry zipEntry = new ZipEntry(
                            STATE_PAYLOAD_DIRECTORY + "/" + entry.getKey());
                    zipEntry.setTime(entry.getValue().lastModified());
                    zip.putNextEntry(zipEntry);
                    MessageDigest digest = MessageDigest.getInstance("SHA-256");
                    try (InputStream input = new BufferedInputStream(
                            new FileInputStream(entry.getValue()))) {
                        int count;
                        while ((count = input.read(buffer)) != -1) {
                            archivedBytes += count;
                            if (archivedBytes > STATE_ARCHIVE_MAX_BYTES) {
                                throw new IOException(
                                        "The save/settings export exceeds 64 MiB.");
                            }
                            digest.update(buffer, 0, count);
                            zip.write(buffer, 0, count);
                        }
                    }
                    zip.closeEntry();
                    hashes.put(entry.getKey(), hexDigest(digest.digest()));
                    completed++;
                    if (completed % 32 == 0) {
                        updateProgress("Archived " + completed + " of "
                                + files.size() + " files…");
                    }
                }

                JSONObject manifest = new JSONObject();
                manifest.put("schemaVersion", STATE_MANIFEST_SCHEMA);
                manifest.put("packageName", host.getPackageName());
                manifest.put("createdAtUtc", Instant.now().toString());
                manifest.put("files", hashes);
                writeZipBytes(
                        zip,
                        STATE_MANIFEST_NAME,
                        manifest.toString(2).getBytes(StandardCharsets.UTF_8));
            }
        } catch (IOException | JSONException | NoSuchAlgorithmException
                | RuntimeException error) {
            try {
                resolver.delete(uri, null, null);
            } catch (RuntimeException ignored) {
                // Some document providers do not permit deleting a failed document.
            }
            throw error;
        }

        Log.i(TAG, "BARONY_ANDROID_STATE_ARCHIVE_EXPORT_COMPLETE files="
                + files.size() + " bytes=" + archivedBytes);
        return TaskResult.success(
                "Saves exported",
                "Exported " + files.size() + " save/settings files to "
                        + getDisplayName(uri) + ".");
    }

    private TaskResult importState(Uri uri)
            throws IOException, JSONException, NoSuchAlgorithmException {
        File destination = host.getBaronyStateImportDirectory();
        File dataImport = host.getBaronyDataImportDirectory();
        if (destination == null || dataImport == null || dataImport.getParentFile() == null) {
            return TaskResult.failure(
                    "Import unavailable",
                    "App-specific external storage is unavailable on this device.");
        }

        File staging = new File(dataImport.getParentFile(), "barony-state-document-import");
        prepareEmptyDirectory(staging);
        try {
            extractArchive(
                    uri,
                    staging,
                    STATE_ARCHIVE_MAX_FILES + 1,
                    STATE_ARCHIVE_MAX_BYTES + 1024L * 1024L,
                    false);
            validateStateStaging(staging);
            replaceDirectory(staging, destination, "barony-state-import-backup");
        } catch (IOException | JSONException | NoSuchAlgorithmException error) {
            deleteRecursively(staging);
            throw error;
        }

        Log.i(TAG, "BARONY_ANDROID_STATE_ARCHIVE_IMPORT_READY");
        if (host.isNativeStartupBlocked()) {
            BaronyActivity.StateImportResult result = host.consumeStagedStateImport();
            if (!result.success) {
                return TaskResult.failure("Save import failed", result.detail);
            }
            return TaskResult.stateApplied(
                    result,
                    "Saves imported",
                    "Imported " + result.importedFiles + " save/settings files.");
        }

        return TaskResult.restart(
                "Save import ready",
                "The archive was verified. Exit now, then open the port again to "
                        + "import the saves and settings before Barony starts.");
    }

    private ExtractionStats extractArchive(
            Uri uri,
            File root,
            int maximumFiles,
            long maximumBytes,
            boolean ownedDataArchive) throws IOException {
        ContentResolver resolver = host.getContentResolver();
        try (InputStream raw = resolver.openInputStream(uri)) {
            if (raw == null) {
                throw new IOException("The selected document could not be opened.");
            }
            try (ZipInputStream zip = new ZipInputStream(new BufferedInputStream(raw))) {
                String rootPath = root.getCanonicalPath() + File.separator;
                Set<String> entries = new HashSet<>();
                byte[] buffer = new byte[COPY_BUFFER_SIZE];
                int files = 0;
                long bytes = 0L;
                ZipEntry entry;
                while ((entry = zip.getNextEntry()) != null) {
                    String name = normalizeArchivePath(entry.getName());
                    if (name.isEmpty()) {
                        zip.closeEntry();
                        continue;
                    }
                    if (!entries.add(name)) {
                        throw new IOException("The archive contains a duplicate path: " + name);
                    }
                    if (entries.size() > maximumFiles) {
                        throw new IOException(
                                "The archive exceeds the " + maximumFiles + " entry limit.");
                    }
                    if (ownedDataArchive && !isAllowedDataArchivePath(name, entry.isDirectory())) {
                        throw new IOException(
                                "The archive contains an unsupported Barony path: " + name);
                    }

                    File output = new File(root, name).getCanonicalFile();
                    if (!output.getPath().startsWith(rootPath)) {
                        throw new IOException("The archive contains an unsafe path: " + name);
                    }
                    if (entry.isDirectory()) {
                        if (!output.mkdirs() && !output.isDirectory()) {
                            throw new IOException("Unable to create directory: " + name);
                        }
                        zip.closeEntry();
                        continue;
                    }

                    files++;
                    if (files > maximumFiles) {
                        throw new IOException(
                                "The archive exceeds the " + maximumFiles + " file limit.");
                    }
                    File parent = output.getParentFile();
                    if (parent == null || (!parent.mkdirs() && !parent.isDirectory())) {
                        throw new IOException("Unable to create the directory for: " + name);
                    }
                    try (OutputStream file = new BufferedOutputStream(
                            new FileOutputStream(output))) {
                        long entryBytes = 0L;
                        int count;
                        while ((count = zip.read(buffer)) != -1) {
                            entryBytes += count;
                            bytes += count;
                            if (bytes > maximumBytes) {
                                throw new IOException(
                                        "The archive exceeds its uncompressed size limit.");
                            }
                            long maximumEntryBytes = ownedDataArchive
                                    ? DATA_ARCHIVE_MAX_ENTRY_BYTES
                                    : STATE_ARCHIVE_MAX_BYTES;
                            if (entryBytes > maximumEntryBytes) {
                                throw new IOException(
                                        "An archive entry exceeds its size limit: " + name);
                            }
                            if ((DATA_MANIFEST_NAME.equals(name)
                                    || STATE_MANIFEST_NAME.equals(name))
                                    && entryBytes > ARCHIVE_MANIFEST_MAX_BYTES) {
                                throw new IOException(
                                        "The archive manifest exceeds 1 MiB.");
                            }
                            file.write(buffer, 0, count);
                        }
                    }
                    zip.closeEntry();
                    if (files % 256 == 0) {
                        updateProgress("Extracted " + files + " files ("
                                + humanBytes(bytes) + ")…");
                    }
                }
                if (files == 0) {
                    throw new IOException("The selected ZIP archive is empty.");
                }
                return new ExtractionStats(files, bytes);
            }
        }
    }

    private void validateStateStaging(File staging)
            throws IOException, JSONException, NoSuchAlgorithmException {
        File manifestFile = new File(staging, STATE_MANIFEST_NAME);
        File payload = new File(staging, STATE_PAYLOAD_DIRECTORY);
        if (!manifestFile.isFile() || !payload.isDirectory()) {
            throw new IOException(
                    "This is not a Barony Android save archive.");
        }
        File[] rootChildren = staging.listFiles();
        if (rootChildren == null) {
            throw new IOException("Unable to inspect the save archive.");
        }
        for (File child : rootChildren) {
            if (!STATE_MANIFEST_NAME.equals(child.getName())
                    && !STATE_PAYLOAD_DIRECTORY.equals(child.getName())) {
                throw new IOException(
                        "Unexpected file in save archive: " + child.getName());
            }
        }

        JSONObject manifest = new JSONObject(new String(
                Files.readAllBytes(manifestFile.toPath()), StandardCharsets.UTF_8));
        if (manifest.optInt("schemaVersion", -1) != STATE_MANIFEST_SCHEMA) {
            throw new IOException("Unsupported save archive version.");
        }
        if (!host.getPackageName().equals(manifest.optString("packageName", ""))) {
            throw new IOException("The save archive belongs to another application.");
        }
        JSONObject hashes = manifest.optJSONObject("files");
        if (hashes == null || hashes.length() == 0
                || hashes.length() > STATE_ARCHIVE_MAX_FILES) {
            throw new IOException("The save archive has an invalid file list.");
        }

        Set<String> expected = new HashSet<>();
        long totalBytes = 0L;
        Iterator<String> iterator = hashes.keys();
        while (iterator.hasNext()) {
            String relativePath = iterator.next();
            if (!isAllowedStatePath(relativePath)) {
                throw new IOException(
                        "The save archive contains a disallowed path: " + relativePath);
            }
            String expectedHash = hashes.optString(relativePath, "");
            if (!expectedHash.matches("(?i)[0-9a-f]{64}")) {
                throw new IOException(
                        "The save archive has an invalid hash for " + relativePath);
            }
            File file = new File(payload, relativePath).getCanonicalFile();
            String payloadRoot = payload.getCanonicalPath() + File.separator;
            if (!file.getPath().startsWith(payloadRoot) || !file.isFile()) {
                throw new IOException(
                        "The save archive is missing: " + relativePath);
            }
            totalBytes += file.length();
            if (totalBytes > STATE_ARCHIVE_MAX_BYTES) {
                throw new IOException("The save archive exceeds 64 MiB.");
            }
            if (!expectedHash.equalsIgnoreCase(sha256(file))) {
                throw new IOException(
                        "The save archive failed its integrity check: " + relativePath);
            }
            expected.add(relativePath);
        }

        LinkedHashMap<String, File> actualFiles = new LinkedHashMap<>();
        collectStateFiles(payload, payload, actualFiles);
        if (!actualFiles.keySet().equals(expected)) {
            throw new IOException(
                    "The save archive payload does not match its manifest.");
        }
    }

    private void runTask(String title, String message, StorageTask task) {
        showProgress(title, message);
        executor.execute(() -> {
            TaskResult result;
            try {
                result = task.run();
            } catch (Exception error) {
                Log.e(TAG, "BARONY_ANDROID_STORAGE_OPERATION_FAILED", error);
                result = TaskResult.failure(
                        "Operation failed",
                        error.getMessage() == null
                                ? error.getClass().getSimpleName()
                                : error.getMessage());
            }
            TaskResult completed = result;
            host.runOnUiThread(() -> finishTask(completed));
        });
    }

    private void showProgress(String title, String message) {
        if (operationDialog != null) {
            operationDialog.dismiss();
        }
        operationDialog = new AlertDialog.Builder(host)
                .setTitle(title)
                .setMessage(message)
                .setCancelable(false)
                .create();
        operationDialog.show();
    }

    private void updateProgress(String message) {
        host.runOnUiThread(() -> {
            if (operationDialog != null && operationDialog.isShowing()) {
                operationDialog.setMessage(message);
            }
        });
    }

    private void finishTask(TaskResult result) {
        if (operationDialog != null) {
            operationDialog.dismiss();
            operationDialog = null;
        }
        if (shuttingDown || host.isFinishing() || host.isDestroyed()) {
            return;
        }
        if (result.completion == Completion.DATA_APPLIED) {
            new AlertDialog.Builder(host)
                    .setTitle(result.title)
                    .setMessage(result.message)
                    .setPositiveButton("Continue", (dialog, which) ->
                            host.onDocumentDataImportApplied())
                    .setCancelable(false)
                    .show();
            return;
        }
        if (result.completion == Completion.STATE_APPLIED) {
            new AlertDialog.Builder(host)
                    .setTitle(result.title)
                    .setMessage(result.message)
                    .setPositiveButton("Continue", (dialog, which) ->
                            host.onDocumentStateImportApplied(result.stateImportResult))
                    .setCancelable(false)
                    .show();
            return;
        }
        if (result.restart) {
            new AlertDialog.Builder(host)
                    .setTitle(result.title)
                    .setMessage(result.message)
                    .setPositiveButton("Exit now", (dialog, which) ->
                            host.requestStorageRestart())
                    .setNegativeButton("Later", null)
                    .show();
            return;
        }
        AlertDialog.Builder builder = new AlertDialog.Builder(host)
                .setTitle(result.title)
                .setMessage(result.message)
                .setPositiveButton("OK", null);
        if (!result.success && host.isNativeStartupBlocked()) {
            builder.setOnDismissListener(dialog -> host.showCurrentDataRequirement());
        }
        builder.show();
    }

    void shutdown() {
        shuttingDown = true;
        executor.shutdownNow();
        if (operationDialog != null) {
            operationDialog.dismiss();
            operationDialog = null;
        }
    }

    private String getDisplayName(Uri uri) {
        try (android.database.Cursor cursor = host.getContentResolver().query(
                uri, new String[] { OpenableColumns.DISPLAY_NAME },
                null, null, null)) {
            if (cursor != null && cursor.moveToFirst()) {
                int index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME);
                if (index >= 0) {
                    return cursor.getString(index);
                }
            }
        } catch (RuntimeException ignored) {
            // Fall back to a generic description.
        }
        return "the selected document";
    }

    private static void collectStateFiles(
            File root, File current, LinkedHashMap<String, File> result)
            throws IOException {
        if (!current.exists()) {
            return;
        }
        if (Files.isSymbolicLink(current.toPath())) {
            throw new IOException("Symbolic links are not allowed in save archives.");
        }
        if (current.isFile()) {
            String relative = root.toPath().relativize(current.toPath()).toString()
                    .replace(File.separatorChar, '/');
            if (!isAllowedStatePath(relative)) {
                throw new IOException("Disallowed save path: " + relative);
            }
            result.put(relative, current);
            return;
        }
        File[] children = current.listFiles();
        if (children == null) {
            throw new IOException("Unable to list " + current);
        }
        java.util.Arrays.sort(children, (left, right) ->
                left.getName().compareToIgnoreCase(right.getName()));
        for (File child : children) {
            collectStateFiles(root, child, result);
        }
    }

    private static boolean isAllowedStatePath(String relativePath) {
        if (relativePath == null || relativePath.isEmpty()
                || relativePath.startsWith("/") || relativePath.contains("\\")
                || relativePath.contains(":")) {
            return false;
        }
        String[] parts = relativePath.split("/");
        if (parts.length < 2
                || (!"savegames".equals(parts[0]) && !"config".equals(parts[0]))) {
            return false;
        }
        for (String part : parts) {
            if (part.isEmpty() || ".".equals(part) || "..".equals(part)) {
                return false;
            }
        }
        return true;
    }

    private static boolean isAllowedDataArchivePath(String path, boolean directory) {
        if (DATA_IMPORT_READY.equals(path) || path.endsWith("/" + DATA_IMPORT_READY)) {
            return false;
        }
        int separator = path.indexOf('/');
        String root = separator >= 0 ? path.substring(0, separator) : path;
        if (DATA_DIRECTORIES.contains(root)) {
            String lower = path.toLowerCase(Locale.ROOT);
            return !lower.endsWith("/models.cache")
                    && !lower.endsWith(".ogv");
        }
        return !directory && separator < 0 && DATA_ROOT_FILES.contains(path);
    }

    private static String normalizeArchivePath(String raw) throws IOException {
        if (raw == null || raw.indexOf('\0') >= 0 || raw.contains("\\")
                || raw.startsWith("/") || raw.contains(":") || raw.length() > 1024) {
            throw new IOException("The archive contains an unsafe path.");
        }
        String path = raw;
        while (path.startsWith("./")) {
            path = path.substring(2);
        }
        while (path.endsWith("/")) {
            path = path.substring(0, path.length() - 1);
        }
        if (path.isEmpty()) {
            return "";
        }
        for (String part : path.split("/")) {
            if (part.isEmpty() || ".".equals(part) || "..".equals(part)) {
                throw new IOException("The archive contains an unsafe path: " + raw);
            }
        }
        return path;
    }

    private static void prepareEmptyDirectory(File directory) throws IOException {
        if (directory.exists() && !deleteRecursively(directory)) {
            throw new IOException("Unable to clear staging directory: " + directory);
        }
        if (!directory.mkdirs() && !directory.isDirectory()) {
            throw new IOException("Unable to create staging directory: " + directory);
        }
    }

    private static File promoteDirectory(
            File source, File destination, String backupName) throws IOException {
        File parent = destination.getParentFile();
        if (parent == null) {
            throw new IOException("The destination has no parent directory.");
        }
        File backup = new File(parent, backupName);
        if (backup.exists() && !deleteRecursively(backup)) {
            throw new IOException("Unable to clear previous import backup.");
        }

        boolean hadDestination = destination.exists();
        if (hadDestination) {
            movePath(destination, backup);
        }
        try {
            movePath(source, destination);
        } catch (IOException error) {
            if (hadDestination && backup.exists() && !destination.exists()) {
                try {
                    movePath(backup, destination);
                } catch (IOException rollbackError) {
                    error.addSuppressed(rollbackError);
                }
            }
            throw error;
        }
        return hadDestination ? backup : null;
    }

    private static void rollbackPromotedDirectory(
            File destination, File backup) throws IOException {
        if (destination.exists() && !deleteRecursively(destination)) {
            throw new IOException("Unable to remove the invalid imported data.");
        }
        if (backup != null && backup.exists()) {
            movePath(backup, destination);
        }
    }

    private static void removeCompletedBackup(File backup) {
        if (backup != null && backup.exists() && !deleteRecursively(backup)) {
            Log.w(TAG, "Unable to remove completed import backup " + backup);
        }
    }

    private static void replaceDirectory(
            File source, File destination, String backupName) throws IOException {
        File backup = promoteDirectory(source, destination, backupName);
        removeCompletedBackup(backup);
    }

    private static String hexDigest(byte[] bytes) {
        StringBuilder result = new StringBuilder(bytes.length * 2);
        for (byte value : bytes) {
            result.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        }
        return result.toString();
    }

    private static void movePath(File source, File destination) throws IOException {
        try {
            Files.move(
                    source.toPath(),
                    destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException error) {
            Files.move(source.toPath(), destination.toPath());
        }
    }

    private static boolean deleteRecursively(File file) {
        File[] children = file.listFiles();
        if (children != null) {
            for (File child : children) {
                if (!deleteRecursively(child)) {
                    return false;
                }
            }
        }
        return !file.exists() || file.delete();
    }

    private static void writeZipBytes(ZipOutputStream zip, String name, byte[] bytes)
            throws IOException {
        zip.putNextEntry(new ZipEntry(name));
        zip.write(bytes);
        zip.closeEntry();
    }

    private static String sha256(File file)
            throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] buffer = new byte[COPY_BUFFER_SIZE];
        try (InputStream input = new BufferedInputStream(new FileInputStream(file))) {
            int count;
            while ((count = input.read(buffer)) != -1) {
                digest.update(buffer, 0, count);
            }
        }
        return hexDigest(digest.digest());
    }

    private static String humanBytes(long bytes) {
        if (bytes >= 1024L * 1024L * 1024L) {
            return String.format(
                    Locale.ROOT, "%.1f GiB", bytes / (1024.0 * 1024.0 * 1024.0));
        }
        if (bytes >= 1024L * 1024L) {
            return String.format(Locale.ROOT, "%.1f MiB", bytes / (1024.0 * 1024.0));
        }
        return String.format(Locale.ROOT, "%.1f KiB", bytes / 1024.0);
    }

    private interface StorageTask {
        TaskResult run() throws Exception;
    }

    private enum Completion {
        NONE,
        DATA_APPLIED,
        STATE_APPLIED
    }

    private static final class ExtractionStats {
        final int files;
        final long bytes;

        ExtractionStats(int files, long bytes) {
            this.files = files;
            this.bytes = bytes;
        }
    }

    private static final class TaskResult {
        final boolean success;
        final String title;
        final String message;
        final boolean restart;
        final Completion completion;
        final BaronyActivity.StateImportResult stateImportResult;

        private TaskResult(
                boolean success,
                String title,
                String message,
                boolean restart,
                Completion completion,
                BaronyActivity.StateImportResult stateImportResult) {
            this.success = success;
            this.title = title;
            this.message = message;
            this.restart = restart;
            this.completion = completion;
            this.stateImportResult = stateImportResult;
        }

        static TaskResult success(String title, String message) {
            return new TaskResult(
                    true, title, message, false, Completion.NONE, null);
        }

        static TaskResult failure(String title, String message) {
            return new TaskResult(
                    false, title, message, false, Completion.NONE, null);
        }

        static TaskResult restart(String title, String message) {
            return new TaskResult(
                    true, title, message, true, Completion.NONE, null);
        }

        static TaskResult dataApplied(String title, String message) {
            return new TaskResult(
                    true, title, message, false, Completion.DATA_APPLIED, null);
        }

        static TaskResult stateApplied(
                BaronyActivity.StateImportResult result,
                String title,
                String message) {
            return new TaskResult(
                    true, title, message, false, Completion.STATE_APPLIED, result);
        }
    }
}
