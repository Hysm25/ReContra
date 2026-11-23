package com.recontra.game;

import org.libsdl.app.SDLActivity;
import android.os.Bundle;
import android.content.Intent;
import android.net.Uri;
import android.widget.Toast;
import java.io.File;
import java.io.InputStream;
import java.io.FileOutputStream;

public class MainActivity extends SDLActivity {
    private static final int REQUEST_ROM_PICKER = 1001;

    @Override
    protected String[] getLibraries() {
        return new String[] {
            "SDL3",
            "main"
        };
    }

    @Override
    protected String getMainSharedObject() {
        return "libmain.so";
    }

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        checkAndPromptRom();
    }

    private void checkAndPromptRom() {
        File extDir = getExternalFilesDir(null);
        boolean romExists = false;
        if (extDir != null) {
            File rom1 = new File(extDir, "Contra (USA).nes");
            File rom2 = new File(extDir, "contra.nes");
            if (rom1.exists() || rom2.exists()) {
                romExists = true;
            }
        }
        File common1 = new File("/sdcard/Documents/Codes/ReContra/Contra (USA).nes");
        File common2 = new File("/sdcard/Download/Contra (USA).nes");
        if (common1.exists() || common2.exists()) {
            romExists = true;
        }

        if (!romExists) {
            Toast.makeText(this, "Select authentic Contra (USA).nes ROM to start", Toast.LENGTH_LONG).show();
            launchRomPicker();
        }
    }

    public void launchRomPicker() {
        Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
        intent.addCategory(Intent.CATEGORY_OPENABLE);
        intent.setType("*/*");
        try {
            startActivityForResult(intent, REQUEST_ROM_PICKER);
        } catch (Exception e) {
            e.printStackTrace();
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode == REQUEST_ROM_PICKER && resultCode == RESULT_OK && data != null) {
            Uri uri = data.getData();
            if (uri != null) {
                copyRomFromUri(uri);
            }
        }
    }

    private void copyRomFromUri(Uri uri) {
        File destDir = getExternalFilesDir(null);
        if (destDir == null) destDir = getFilesDir();
        File destFile = new File(destDir, "Contra (USA).nes");
        try (InputStream in = getContentResolver().openInputStream(uri);
             FileOutputStream out = new FileOutputStream(destFile)) {
            byte[] buf = new byte[8192];
            int len;
            while ((len = in.read(buf)) > 0) {
                out.write(buf, 0, len);
            }
            Toast.makeText(this, "ROM loaded successfully! Restarting game...", Toast.LENGTH_SHORT).show();
            finish();
            startActivity(getIntent());
        } catch (Exception e) {
            Toast.makeText(this, "Failed to copy ROM: " + e.getMessage(), Toast.LENGTH_LONG).show();
        }
    }
}
