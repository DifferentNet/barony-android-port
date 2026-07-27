package com.zhdan.baronyport;

import android.app.AlertDialog;
import android.os.Bundle;
import android.util.Log;
import android.view.KeyEvent;
import android.view.View;
import android.view.ViewGroup;

import org.libsdl.app.SDLActivity;
import org.json.JSONException;
import org.json.JSONObject;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.ArrayList;
import java.util.HashSet;
import java.util.Iterator;
import java.util.List;
import java.util.Locale;
import java.util.Set;

public final class BaronyActivity extends SDLActivity {
    private static final String TAG = "BaronyAndroid";
    private static final int DATA_MANIFEST_SCHEMA = 1;
    private static final String EXPECTED_GAME_VERSION = "5.0.2";
    private static final String EXPECTED_SOURCE_COMMIT =
            "962a5ce36d10207beef7d8673876e0cebf8e76e4";
    private static final String DATA_MANIFEST_NAME = ".barony-android-data.json";
    private static final int STATE_MANIFEST_SCHEMA = 1;
    private static final String STATE_IMPORT_DIRECTORY = "barony-state-import";
    private static final String STATE_IMPORT_MANIFEST = "manifest.json";
    private static final int STATE_IMPORT_MAX_FILES = 512;
    private static final long STATE_IMPORT_MAX_BYTES = 64L * 1024L * 1024L;
    private static final String[] REQUIRED_DATA_DIRECTORIES = {
            "books", "data", "fonts", "images", "items", "lang", "maps", "models",
            "music", "sound"
    };
    private static final String[] REQUIRED_DATA_FILES = {
            "gamecontrollerdb.txt",
            "npcnames-female.txt",
            "npcnames-male.txt",
            "playernames-female.txt",
            "playernames-male.txt",
            "scores.dat",
            "scores_multiplayer.dat",
            "lang/en.txt",
            "images/system/font8x8.png",
            "maps/start.lmp",
            "models/models.txt",
            "music/mines00.ogg",
            "sound/sounds.txt"
    };
    private static final String[] CRITICAL_HASH_FILES = {
            "lang/en.txt",
            "maps/start.lmp",
            "models/models.txt",
            "sound/sounds.txt"
    };
    private static final String[] EXPECTED_CRITICAL_HASHES = {
            "153ef608caafea9226db4e006ad8d778bfe675cf006227efe0fb5c5cac551f40",
            "40a57fb4e5b1caed5f03599077db368f414970ebcd9aa169fdaeabeb9e6bf04d",
            "d5344cb2891baf871d8a09aa25aeeefb60cb633f4c1a327e46d40d823bdd949c",
            "f4da80b451d4023323f33e8edc555ef0698de2e46629fd7b710aab5f7cd7eb1e"
    };

    private TouchControlsView touchControls;
    private File dataDirectory;
    private File outputDirectory;
    private File externalFilesDirectory;
    private File stateImportDirectory;
    private View blockedSdlSurface;
    private AlertDialog dataDialog;
    private boolean startupBlocked;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        if (!BuildConfig.BARONY_BUILD_GAME) {
            return;
        }

        prepareStorageDirectories();
        StateImportResult importResult = importStagedUserState();
        if (!importResult.success) {
            blockNativeStartup();
            if (mLayout != null) {
                mLayout.post(() -> showStateImportDialog(importResult));
            }
            return;
        }
        DataValidation validation = validateGameData();
        if (!validation.valid) {
            blockNativeStartup();
            if (mLayout != null) {
                mLayout.post(() -> showDataDialog(validation));
            }
            return;
        }
        Log.i(TAG, "BARONY_ANDROID_DATA_VALIDATION_READY version="
                + EXPECTED_GAME_VERSION + " source=" + EXPECTED_SOURCE_COMMIT);
        addTouchControls();
    }

    @Override
    protected String[] getLibraries() {
        if (BuildConfig.BARONY_BUILD_GAME) {
            return new String[] { "SDL2", "barony_game" };
        }
        return new String[] { "SDL2", "main" };
    }

    @Override
    protected String[] getArguments() {
        if (!BuildConfig.BARONY_BUILD_GAME) {
            return super.getArguments();
        }

        prepareStorageDirectories();

        Log.i(TAG, "BARONY_ANDROID_RUNTIME_ACTIVITY_READY");
        Log.i(TAG, "BARONY_ANDROID_DATA_PATH=" + dataDirectory.getAbsolutePath());
        Log.i(TAG, "BARONY_ANDROID_OUTPUT_PATH=" + outputDirectory.getAbsolutePath());
        return new String[] {
            "-datadir=" + dataDirectory.getAbsolutePath(),
            "-outputdir=" + outputDirectory.getAbsolutePath(),
            "-skipintro"
        };
    }

    private void prepareStorageDirectories() {
        if (dataDirectory == null) {
            externalFilesDirectory = getExternalFilesDir(null);
            File dataRoot = externalFilesDirectory;
            if (dataRoot == null) {
                dataRoot = getFilesDir();
            }
            dataDirectory = new File(dataRoot, "barony-data");
            if (externalFilesDirectory != null) {
                stateImportDirectory = new File(
                        externalFilesDirectory, STATE_IMPORT_DIRECTORY);
            }
        }
        if (outputDirectory == null) {
            outputDirectory = new File(getFilesDir(), "barony-output");
        }
        if (!dataDirectory.mkdirs() && !dataDirectory.isDirectory()) {
            throw new IllegalStateException("Unable to create Barony data directory: " + dataDirectory);
        }
        if (!outputDirectory.mkdirs() && !outputDirectory.isDirectory()) {
            throw new IllegalStateException("Unable to create Barony output directory: " + outputDirectory);
        }
    }

    private void addTouchControls() {
        if (touchControls != null || mLayout == null) {
            return;
        }
        touchControls = new TouchControlsView(this);
        mLayout.addView(touchControls, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        touchControls.bringToFront();
    }

    private void blockNativeStartup() {
        startupBlocked = true;
        if (mLayout != null && mLayout.getChildCount() > 0) {
            blockedSdlSurface = mLayout.getChildAt(0);
            mLayout.removeView(blockedSdlSurface);
        }
    }

    private void resumeNativeStartup() {
        if (!startupBlocked || blockedSdlSurface == null || mLayout == null) {
            return;
        }
        startupBlocked = false;
        mLayout.addView(blockedSdlSurface, 0, new ViewGroup.LayoutParams(
                ViewGroup.LayoutParams.MATCH_PARENT,
                ViewGroup.LayoutParams.MATCH_PARENT));
        addTouchControls();
        blockedSdlSurface.requestFocus();
        resumeNativeThread();
    }

    private StateImportResult importStagedUserState() {
        if (stateImportDirectory == null) {
            return StateImportResult.success(0);
        }
        File manifestFile = new File(stateImportDirectory, STATE_IMPORT_MANIFEST);
        if (!manifestFile.isFile()) {
            return StateImportResult.success(0);
        }

        Log.i(TAG, "BARONY_ANDROID_STATE_IMPORT_READY path="
                + stateImportDirectory.getAbsolutePath());
        try {
            String manifestText = new String(
                    Files.readAllBytes(manifestFile.toPath()), StandardCharsets.UTF_8);
            JSONObject manifest = new JSONObject(manifestText);
            if (manifest.optInt("schemaVersion", -1) != STATE_MANIFEST_SCHEMA) {
                return stateImportFailure("Unsupported state-backup manifest schema.");
            }
            if (!getPackageName().equals(manifest.optString("packageName", ""))) {
                return stateImportFailure("The state backup belongs to another application.");
            }

            JSONObject hashes = manifest.optJSONObject("files");
            if (hashes == null || hashes.length() == 0
                    || hashes.length() > STATE_IMPORT_MAX_FILES) {
                return stateImportFailure("The state backup has an invalid file list.");
            }

            File payloadRoot = new File(stateImportDirectory, "payload");
            String payloadCanonical = payloadRoot.getCanonicalPath() + File.separator;
            String outputCanonical = outputDirectory.getCanonicalPath() + File.separator;
            List<StateImportEntry> entries = new ArrayList<>();
            Set<String> expectedPaths = new HashSet<>();
            long totalBytes = 0L;

            Iterator<String> keys = hashes.keys();
            while (keys.hasNext()) {
                String relativePath = keys.next();
                if (!isAllowedStatePath(relativePath)) {
                    return stateImportFailure(
                            "The state backup contains a disallowed path: " + relativePath);
                }
                String expectedHash = hashes.optString(relativePath, "");
                if (!expectedHash.matches("(?i)[0-9a-f]{64}")) {
                    return stateImportFailure(
                            "The state backup has an invalid hash for " + relativePath);
                }

                File source = new File(payloadRoot, relativePath).getCanonicalFile();
                File destination = new File(outputDirectory, relativePath).getCanonicalFile();
                if (!source.getPath().startsWith(payloadCanonical)
                        || !destination.getPath().startsWith(outputCanonical)
                        || !source.isFile()) {
                    return stateImportFailure(
                            "The state backup file is missing or unsafe: " + relativePath);
                }

                totalBytes += source.length();
                if (totalBytes > STATE_IMPORT_MAX_BYTES) {
                    return stateImportFailure("The state backup exceeds the 64 MiB limit.");
                }
                if (!expectedHash.equalsIgnoreCase(sha256(source))) {
                    return stateImportFailure(
                            "The state backup failed its integrity check: " + relativePath);
                }
                expectedPaths.add(relativePath);
                entries.add(new StateImportEntry(relativePath, source, destination));
            }

            Set<String> stagedPaths = new HashSet<>();
            collectRelativeFiles(payloadRoot, payloadRoot, stagedPaths);
            if (!stagedPaths.equals(expectedPaths)) {
                return stateImportFailure(
                        "The staged state files do not match the backup manifest.");
            }

            for (StateImportEntry entry : entries) {
                File parent = entry.destination.getParentFile();
                if (parent == null || (!parent.mkdirs() && !parent.isDirectory())) {
                    return stateImportFailure(
                            "Unable to create the restore directory for " + entry.relativePath);
                }
                File temporary = File.createTempFile(".barony-state-", ".tmp", parent);
                try {
                    Files.copy(entry.source.toPath(), temporary.toPath(),
                            StandardCopyOption.REPLACE_EXISTING);
                    moveReplacing(temporary, entry.destination);
                } finally {
                    if (temporary.exists() && !temporary.delete()) {
                        Log.w(TAG, "Unable to remove temporary state file " + temporary);
                    }
                }
            }

            if (!manifestFile.delete()) {
                return stateImportFailure(
                        "State was restored, but the import marker could not be consumed.");
            }
            if (!deleteRecursively(stateImportDirectory)) {
                Log.w(TAG, "Unable to completely remove consumed state staging directory");
            }
            Log.i(TAG, "BARONY_ANDROID_STATE_IMPORT_COMPLETE files=" + entries.size()
                    + " bytes=" + totalBytes);
            return StateImportResult.success(entries.size());
        } catch (IOException | JSONException | NoSuchAlgorithmException error) {
            Log.e(TAG, "BARONY_ANDROID_STATE_IMPORT_FAILED", error);
            return StateImportResult.failure(
                    "The staged state backup could not be restored: " + error.getMessage());
        }
    }

    private StateImportResult stateImportFailure(String detail) {
        Log.e(TAG, "BARONY_ANDROID_STATE_IMPORT_FAILED detail=" + detail);
        return StateImportResult.failure(detail);
    }

    private static boolean isAllowedStatePath(String relativePath) {
        if (relativePath == null || relativePath.isEmpty()
                || relativePath.startsWith("/") || relativePath.contains("\\")
                || relativePath.contains(":")) {
            return false;
        }
        String[] parts = relativePath.split("/");
        if (parts.length < 2
                || (!("savegames".equals(parts[0])) && !("config".equals(parts[0])))) {
            return false;
        }
        for (String part : parts) {
            if (part.isEmpty() || ".".equals(part) || "..".equals(part)) {
                return false;
            }
        }
        return true;
    }

    private static void collectRelativeFiles(
            File root, File current, Set<String> relativeFiles) throws IOException {
        File[] children = current.listFiles();
        if (children == null) {
            throw new IOException("Unable to list staged state directory: " + current);
        }
        for (File child : children) {
            if (Files.isSymbolicLink(child.toPath())) {
                throw new IOException("Symbolic links are not allowed in staged state: " + child);
            }
            if (child.isDirectory()) {
                collectRelativeFiles(root, child, relativeFiles);
            } else if (child.isFile()) {
                String relative = root.toPath().relativize(child.toPath()).toString()
                        .replace(File.separatorChar, '/');
                relativeFiles.add(relative);
            } else {
                throw new IOException("Unsupported staged state entry: " + child);
            }
        }
    }

    private static void moveReplacing(File source, File destination) throws IOException {
        try {
            Files.move(source.toPath(), destination.toPath(),
                    StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
        } catch (AtomicMoveNotSupportedException error) {
            Files.move(source.toPath(), destination.toPath(),
                    StandardCopyOption.REPLACE_EXISTING);
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

    private DataValidation validateGameData() {
        for (String relativePath : REQUIRED_DATA_DIRECTORIES) {
            File directory = new File(dataDirectory, relativePath);
            if (!directory.isDirectory()) {
                return DataValidation.failure("missing_data",
                        "Required directory is missing: " + relativePath);
            }
        }
        for (String relativePath : REQUIRED_DATA_FILES) {
            File file = new File(dataDirectory, relativePath);
            if (!file.isFile() || file.length() <= 0L) {
                return DataValidation.failure("missing_data",
                        "Required file is missing or empty: " + relativePath);
            }
        }

        File manifestFile = new File(dataDirectory, DATA_MANIFEST_NAME);
        if (!manifestFile.isFile()) {
            DataValidation copiedDataValidation = validatePinnedCriticalFiles();
            if (!copiedDataValidation.valid) {
                return copiedDataValidation;
            }
            try {
                writeGeneratedDataManifest(manifestFile);
                Log.i(TAG, "BARONY_ANDROID_DATA_MANIFEST_CREATED path="
                        + manifestFile.getAbsolutePath());
                return DataValidation.success();
            } catch (IOException | JSONException error) {
                Log.e(TAG, "Unable to create the Android data manifest", error);
                return DataValidation.failure("manifest_create_failed",
                        "The files match Barony " + EXPECTED_GAME_VERSION
                                + ", but the app could not create its data manifest: "
                                + error.getMessage());
            }
        }

        try {
            String manifestText = new String(
                    Files.readAllBytes(manifestFile.toPath()), StandardCharsets.UTF_8);
            JSONObject manifest = new JSONObject(manifestText);
            if (manifest.optInt("schemaVersion", -1) != DATA_MANIFEST_SCHEMA) {
                return DataValidation.failure("manifest_schema",
                        "The deployment manifest format is unsupported.");
            }
            String gameVersion = manifest.optString("gameVersion", "");
            String sourceCommit = manifest.optString("sourceCommit", "");
            if (!EXPECTED_GAME_VERSION.equals(gameVersion)
                    || !EXPECTED_SOURCE_COMMIT.equalsIgnoreCase(sourceCommit)) {
                return DataValidation.failure("version_mismatch",
                        "Expected Barony " + EXPECTED_GAME_VERSION + " data from source "
                                + shortCommit(EXPECTED_SOURCE_COMMIT) + ", but found version "
                                + printableValue(gameVersion) + " from "
                                + printableValue(shortCommit(sourceCommit)) + ".");
            }

            JSONObject criticalFiles = manifest.optJSONObject("criticalFiles");
            if (criticalFiles == null) {
                return DataValidation.failure("manifest_hashes",
                        "The deployment manifest does not contain integrity checks.");
            }
            for (int index = 0; index < CRITICAL_HASH_FILES.length; ++index) {
                String relativePath = CRITICAL_HASH_FILES[index];
                String pinnedHash = EXPECTED_CRITICAL_HASHES[index];
                String expectedHash = criticalFiles.optString(relativePath, "");
                if (expectedHash.isEmpty()) {
                    return DataValidation.failure("manifest_hashes",
                            "The deployment manifest is missing a hash for " + relativePath + ".");
                }
                if (!pinnedHash.equalsIgnoreCase(expectedHash)) {
                    return DataValidation.failure("version_mismatch",
                            "The deployment manifest does not describe the supported Barony "
                                    + EXPECTED_GAME_VERSION + " file: " + relativePath);
                }
                String actualHash = sha256(new File(dataDirectory, relativePath));
                if (!pinnedHash.equalsIgnoreCase(actualHash)) {
                    return DataValidation.failure("integrity_mismatch",
                            "The copied file does not match Barony " + EXPECTED_GAME_VERSION
                                    + ": " + relativePath);
                }
            }
            return DataValidation.success();
        } catch (IOException | JSONException | NoSuchAlgorithmException error) {
            Log.e(TAG, "Unable to validate deployed game data", error);
            return DataValidation.failure("manifest_invalid",
                    "The deployment manifest could not be read: " + error.getMessage());
        }
    }

    private DataValidation validatePinnedCriticalFiles() {
        try {
            for (int index = 0; index < CRITICAL_HASH_FILES.length; ++index) {
                String relativePath = CRITICAL_HASH_FILES[index];
                String actualHash = sha256(new File(dataDirectory, relativePath));
                if (!EXPECTED_CRITICAL_HASHES[index].equalsIgnoreCase(actualHash)) {
                    return DataValidation.failure("version_mismatch",
                            "The copied file does not match Barony " + EXPECTED_GAME_VERSION
                                    + ": " + relativePath
                                    + ". Verify the installed files in Steam and copy them again.");
                }
            }
            return DataValidation.success();
        } catch (IOException | NoSuchAlgorithmException error) {
            Log.e(TAG, "Unable to validate manually copied game data", error);
            return DataValidation.failure("data_unreadable",
                    "The copied game data could not be read: " + error.getMessage());
        }
    }

    private void writeGeneratedDataManifest(File manifestFile)
            throws IOException, JSONException {
        JSONObject criticalFiles = new JSONObject();
        for (int index = 0; index < CRITICAL_HASH_FILES.length; ++index) {
            criticalFiles.put(CRITICAL_HASH_FILES[index], EXPECTED_CRITICAL_HASHES[index]);
        }

        JSONObject manifest = new JSONObject();
        manifest.put("schemaVersion", DATA_MANIFEST_SCHEMA);
        manifest.put("gameVersion", EXPECTED_GAME_VERSION);
        manifest.put("sourceCommit", EXPECTED_SOURCE_COMMIT);
        manifest.put("deployedAtUtc", java.time.Instant.now().toString());
        manifest.put("deploymentMethod", "manual-copy");
        manifest.put("criticalFiles", criticalFiles);

        File temporaryManifest = new File(
                manifestFile.getParentFile(), DATA_MANIFEST_NAME + ".tmp");
        Files.write(
                temporaryManifest.toPath(),
                manifest.toString(2).getBytes(StandardCharsets.UTF_8));
        try {
            Files.move(
                    temporaryManifest.toPath(),
                    manifestFile.toPath(),
                    StandardCopyOption.REPLACE_EXISTING,
                    StandardCopyOption.ATOMIC_MOVE);
        } catch (AtomicMoveNotSupportedException ignored) {
            Files.move(
                    temporaryManifest.toPath(),
                    manifestFile.toPath(),
                    StandardCopyOption.REPLACE_EXISTING);
        }
    }

    private void showDataDialog(DataValidation validation) {
        if (isFinishing() || isDestroyed()) {
            return;
        }
        if (dataDialog != null) {
            dataDialog.dismiss();
        }
        Log.w(TAG, "BARONY_ANDROID_DATA_VALIDATION_FAILED reason="
                + validation.reason + " detail=" + validation.detail);

        String message = "Requires data from an owned Barony "
                + EXPECTED_GAME_VERSION + " PC installation.\n\n"
                + validation.detail + "\n\n"
                + "Copy the contents of the PC Barony folder into:\n"
                + "Android/data/com.zhdan.baronyport/files/barony-data\n\n"
                + "The maps, models, music, and other folders must be directly inside "
                + "barony-data. After copying, select Retry.\n\n"
                + "If Android blocks this folder, use a PC with USB/ADB and "
                + "tools\\deploy-menu-data.ps1.";

        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(validation.reason.equals("version_mismatch")
                        ? "Unsupported Barony game data"
                        : "Barony game data required")
                .setMessage(message)
                .setCancelable(false)
                .setPositiveButton("Retry", (dialog, which) -> retryDataValidation())
                .setNegativeButton("Exit", (dialog, which) -> finish());
        dataDialog = builder.create();
        dataDialog.setOnDismissListener(dialog -> dataDialog = null);
        dataDialog.show();
        Log.i(TAG, "BARONY_ANDROID_DATA_DIALOG_SHOWN reason=" + validation.reason);
    }

    private void retryDataValidation() {
        Log.i(TAG, "BARONY_ANDROID_DATA_RETRY");
        DataValidation validation = validateGameData();
        if (validation.valid) {
            Log.i(TAG, "BARONY_ANDROID_DATA_VALIDATION_READY version="
                    + EXPECTED_GAME_VERSION + " source=" + EXPECTED_SOURCE_COMMIT);
            resumeNativeStartup();
            Log.i(TAG, "BARONY_ANDROID_DATA_RETRY_ACCEPTED");
        } else {
            mLayout.post(() -> showDataDialog(validation));
        }
    }

    private void showStateImportDialog(StateImportResult result) {
        if (isFinishing() || isDestroyed()) {
            return;
        }
        if (dataDialog != null) {
            dataDialog.dismiss();
        }
        String message = "A staged Barony save/settings backup could not be restored.\n\n"
                + result.detail + "\n\n"
                + "The staged backup was preserved. Fix or redeploy it, then select Retry.";
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle("Barony state restore failed")
                .setMessage(message)
                .setCancelable(false)
                .setPositiveButton("Retry", (dialog, which) -> retryStateImport())
                .setNegativeButton("Exit", (dialog, which) -> finish());
        dataDialog = builder.create();
        dataDialog.setOnDismissListener(dialog -> dataDialog = null);
        dataDialog.show();
        Log.i(TAG, "BARONY_ANDROID_STATE_IMPORT_DIALOG_SHOWN");
    }

    private void retryStateImport() {
        Log.i(TAG, "BARONY_ANDROID_STATE_IMPORT_RETRY");
        StateImportResult result = importStagedUserState();
        if (!result.success) {
            mLayout.post(() -> showStateImportDialog(result));
            return;
        }

        DataValidation validation = validateGameData();
        if (!validation.valid) {
            mLayout.post(() -> showDataDialog(validation));
            return;
        }
        Log.i(TAG, "BARONY_ANDROID_DATA_VALIDATION_READY version="
                + EXPECTED_GAME_VERSION + " source=" + EXPECTED_SOURCE_COMMIT);
        resumeNativeStartup();
        Log.i(TAG, "BARONY_ANDROID_STATE_IMPORT_RETRY_ACCEPTED");
    }

    private static String sha256(File file)
            throws IOException, NoSuchAlgorithmException {
        MessageDigest digest = MessageDigest.getInstance("SHA-256");
        byte[] bytes = Files.readAllBytes(file.toPath());
        byte[] hash = digest.digest(bytes);
        StringBuilder result = new StringBuilder(hash.length * 2);
        for (byte value : hash) {
            result.append(String.format(Locale.ROOT, "%02x", value & 0xff));
        }
        return result.toString();
    }

    private static String printableValue(String value) {
        return value == null || value.isEmpty() ? "<missing>" : value;
    }

    private static String shortCommit(String commit) {
        if (commit == null || commit.isEmpty()) {
            return "";
        }
        return commit.substring(0, Math.min(8, commit.length()));
    }

    /** Called from the native game loop when Barony changes UI context. */
    public void setTouchLayoutMode(int mode) {
        runOnUiThread(() -> {
            if (touchControls != null) {
                touchControls.setLayoutMode(mode);
            }
        });
    }

    @SuppressWarnings("deprecation")
    @Override
    public void onBackPressed() {
        if (startupBlocked) {
            finish();
            return;
        }
        SDLActivity.nativeSendQuit();
    }

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (event.getKeyCode() == KeyEvent.KEYCODE_BACK) {
            if (event.getAction() == KeyEvent.ACTION_UP) {
                if (startupBlocked) {
                    finish();
                } else {
                    SDLActivity.nativeSendQuit();
                }
            }
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    protected void onResume() {
        super.onResume();
        if (touchControls != null) {
            touchControls.onHostResume();
        }
    }

    @Override
    protected void onPause() {
        if (touchControls != null) {
            touchControls.onHostPause();
        }
        super.onPause();
    }

    @Override
    protected void onDestroy() {
        if (dataDialog != null) {
            dataDialog.dismiss();
            dataDialog = null;
        }
        if (touchControls != null) {
            touchControls.shutdown();
            touchControls = null;
        }
        super.onDestroy();
        if (BuildConfig.BARONY_BUILD_GAME && isFinishing()) {
            // Barony's native globals are designed for one main() invocation.
            // Android may otherwise cache this process and call SDL_main again
            // after a launcher restart, which is not a supported re-entry path.
            android.os.Process.killProcess(android.os.Process.myPid());
        }
    }

    private static final class DataValidation {
        final boolean valid;
        final String reason;
        final String detail;

        private DataValidation(boolean valid, String reason, String detail) {
            this.valid = valid;
            this.reason = reason;
            this.detail = detail;
        }

        static DataValidation success() {
            return new DataValidation(true, "ready", "");
        }

        static DataValidation failure(String reason, String detail) {
            return new DataValidation(false, reason, detail);
        }
    }

    private static final class StateImportEntry {
        final String relativePath;
        final File source;
        final File destination;

        StateImportEntry(String relativePath, File source, File destination) {
            this.relativePath = relativePath;
            this.source = source;
            this.destination = destination;
        }
    }

    private static final class StateImportResult {
        final boolean success;
        final int importedFiles;
        final String detail;

        private StateImportResult(boolean success, int importedFiles, String detail) {
            this.success = success;
            this.importedFiles = importedFiles;
            this.detail = detail;
        }

        static StateImportResult success(int importedFiles) {
            return new StateImportResult(true, importedFiles, "");
        }

        static StateImportResult failure(String detail) {
            return new StateImportResult(false, 0, detail);
        }
    }
}
