package com.zhdan.baronyport;

import android.util.Log;

import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.Inet4Address;
import java.net.Inet6Address;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.NetworkInterface;
import java.net.ServerSocket;
import java.net.Socket;
import java.net.SocketException;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.SecureRandom;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/**
 * One-shot HTTP receiver for "Receive from PC". It serves a single upload page
 * and accepts exactly one ZIP upload from a device on the local network.
 *
 * Safeguards: it runs only while the receive dialog is open; it requires the
 * six-digit code shown on screen and stops after five wrong codes; it accepts
 * only clients on private, link-local, or loopback addresses; it enforces a
 * size limit and socket timeouts; and it stops after one successful upload.
 */
final class LanTransferServer {
    interface Listener {
        void onProgress(long receivedBytes, long totalBytes);

        void onReceived(File file, String originalName);

        void onStopped(String reason);
    }

    private static final String TAG = "BaronyAndroid";
    private static final int PREFERRED_PORT = 8765;
    private static final int MAX_HEADER_BYTES = 16 * 1024;
    private static final int SOCKET_TIMEOUT_MS = 60_000;
    private static final int MAX_WRONG_CODES = 5;
    private static final int COPY_BUFFER_SIZE = 128 * 1024;

    private final File destination;
    private final long maximumBytes;
    private final Listener listener;
    private final String code;
    private ServerSocket serverSocket;
    private Thread thread;
    private volatile boolean stopping;
    private int wrongCodes;

    LanTransferServer(File destination, long maximumBytes, Listener listener) {
        this.destination = destination;
        this.maximumBytes = maximumBytes;
        this.listener = listener;
        SecureRandom random = new SecureRandom();
        this.code = String.format(Locale.ROOT, "%06d", random.nextInt(1_000_000));
    }

    String getCode() {
        return code;
    }

    int getPort() {
        return serverSocket == null ? -1 : serverSocket.getLocalPort();
    }

    void start() throws IOException {
        ServerSocket socket = new ServerSocket();
        socket.setReuseAddress(true);
        try {
            socket.bind(new InetSocketAddress(PREFERRED_PORT));
        } catch (IOException portInUse) {
            socket.close();
            socket = new ServerSocket();
            socket.bind(new InetSocketAddress(0));
        }
        serverSocket = socket;
        thread = new Thread(this::serve, "BaronyLanTransfer");
        thread.start();
        Log.i(TAG, "BARONY_ANDROID_LAN_TRANSFER_STARTED port=" + getPort());
    }

    void stop() {
        stopping = true;
        if (serverSocket != null) {
            try {
                serverSocket.close();
            } catch (IOException ignored) {
                // Closing unblocks accept(); nothing else to do.
            }
        }
    }

    /** The device's local-network addresses that a computer can reach. */
    static List<String> getLocalAddresses() {
        List<String> addresses = new ArrayList<>();
        try {
            for (NetworkInterface network : Collections.list(NetworkInterface.getNetworkInterfaces())) {
                if (!network.isUp() || network.isLoopback()) {
                    continue;
                }
                for (InetAddress address : Collections.list(network.getInetAddresses())) {
                    if (address instanceof Inet4Address && address.isSiteLocalAddress()) {
                        addresses.add(address.getHostAddress());
                    }
                }
            }
        } catch (SocketException error) {
            Log.w(TAG, "Unable to list network addresses", error);
        }
        return addresses;
    }

    private void serve() {
        String stopReason = "cancelled";
        try {
            while (!stopping) {
                Socket client;
                try {
                    client = serverSocket.accept();
                } catch (IOException closed) {
                    break;
                }
                try {
                    client.setSoTimeout(SOCKET_TIMEOUT_MS);
                    String result = handle(client);
                    if ("received".equals(result) || "too-many-codes".equals(result)) {
                        stopReason = result;
                        stopping = true;
                    }
                } catch (IOException error) {
                    Log.w(TAG, "BARONY_ANDROID_LAN_TRANSFER_REQUEST_FAILED " + error.getMessage());
                } finally {
                    try {
                        client.close();
                    } catch (IOException ignored) {
                        // The connection is finished either way.
                    }
                }
            }
        } finally {
            stop();
            Log.i(TAG, "BARONY_ANDROID_LAN_TRANSFER_STOPPED reason=" + stopReason);
            listener.onStopped(stopReason);
        }
    }

    private static boolean isLocalClient(InetAddress address) {
        if (address.isLoopbackAddress() || address.isSiteLocalAddress()
                || address.isLinkLocalAddress()) {
            return true;
        }
        if (address instanceof Inet6Address) {
            byte first = address.getAddress()[0];
            return (first & 0xfe) == 0xfc; // unique local fc00::/7
        }
        return false;
    }

    private String handle(Socket client) throws IOException {
        InputStream input = client.getInputStream();
        OutputStream output = client.getOutputStream();
        if (!isLocalClient(client.getInetAddress())) {
            respond(output, 403, "text/plain", "Only devices on the local network may connect.");
            return "rejected";
        }

        String header = readHeader(input);
        if (header == null) {
            respond(output, 400, "text/plain", "Bad request.");
            return "bad-request";
        }
        String[] lines = header.split("\r\n");
        String[] requestLine = lines[0].split(" ");
        if (requestLine.length < 2) {
            respond(output, 400, "text/plain", "Bad request.");
            return "bad-request";
        }
        String method = requestLine[0];
        String path = requestLine[1];

        if ("GET".equals(method) && ("/".equals(path) || "/index.html".equals(path))) {
            respond(output, 200, "text/html; charset=utf-8", UPLOAD_PAGE);
            return "page";
        }
        if (!"POST".equals(method) || !"/upload".equals(path)) {
            respond(output, 404, "text/plain", "Not found.");
            return "not-found";
        }

        String suppliedCode = headerValue(lines, "x-barony-code");
        if (!constantTimeEquals(code, suppliedCode)) {
            wrongCodes++;
            Log.w(TAG, "BARONY_ANDROID_LAN_TRANSFER_WRONG_CODE attempts=" + wrongCodes);
            if (wrongCodes >= MAX_WRONG_CODES) {
                respondJson(output, 403, false,
                        "Too many wrong codes. Open Receive from PC on the TV again.");
                return "too-many-codes";
            }
            respondJson(output, 403, false, "Wrong code. Check the code shown on the TV.");
            return "wrong-code";
        }

        if (headerValue(lines, "transfer-encoding") != null) {
            respondJson(output, 411, false, "Upload size is required.");
            return "bad-request";
        }
        long length;
        try {
            length = Long.parseLong(headerValue(lines, "content-length"));
        } catch (NumberFormatException | NullPointerException error) {
            respondJson(output, 411, false, "Upload size is required.");
            return "bad-request";
        }
        if (length <= 0 || length > maximumBytes) {
            respondJson(output, 413, false, "The file is empty or larger than the 2 GB limit.");
            return "too-large";
        }

        String name = "upload.zip";
        String rawName = headerValue(lines, "x-barony-filename");
        if (rawName != null) {
            try {
                name = URLDecoder.decode(rawName, "UTF-8");
            } catch (IllegalArgumentException ignored) {
                // Keep the generic name.
            }
        }
        if (!name.toLowerCase(Locale.ROOT).endsWith(".zip")) {
            respondJson(output, 415, false, "Choose a .zip file.");
            return "not-zip";
        }

        Log.i(TAG, "BARONY_ANDROID_LAN_TRANSFER_RECEIVING bytes=" + length);
        if (!receiveBody(input, length)) {
            respondJson(output, 400, false, "The upload was interrupted.");
            return "interrupted";
        }
        if (!looksLikeZip(destination)) {
            if (!destination.delete()) {
                Log.w(TAG, "Unable to delete a rejected upload");
            }
            respondJson(output, 415, false, "That file isn't a ZIP archive.");
            return "not-zip";
        }
        respondJson(output, 200, true, "Received. Follow the instructions on the TV.");
        Log.i(TAG, "BARONY_ANDROID_LAN_TRANSFER_RECEIVED bytes=" + length);
        listener.onReceived(destination, name);
        return "received";
    }

    private boolean receiveBody(InputStream input, long length) throws IOException {
        byte[] buffer = new byte[COPY_BUFFER_SIZE];
        long received = 0;
        long lastReport = 0;
        try (OutputStream file = new BufferedOutputStream(new FileOutputStream(destination))) {
            while (received < length) {
                if (stopping) {
                    break;
                }
                int count = input.read(buffer, 0, (int) Math.min(buffer.length, length - received));
                if (count < 0) {
                    break;
                }
                file.write(buffer, 0, count);
                received += count;
                if (received - lastReport >= 4L * 1024 * 1024 || received == length) {
                    lastReport = received;
                    listener.onProgress(received, length);
                }
            }
        } catch (IOException error) {
            // A full disk or dropped connection must not leave a partial file.
            if (destination.exists() && !destination.delete()) {
                Log.w(TAG, "Unable to delete a failed upload");
            }
            throw error;
        }
        if (received != length) {
            if (!destination.delete()) {
                Log.w(TAG, "Unable to delete an interrupted upload");
            }
            return false;
        }
        return true;
    }

    private static boolean looksLikeZip(File file) {
        byte[] magic = new byte[4];
        try (InputStream input = new java.io.FileInputStream(file)) {
            return input.read(magic) == 4 && magic[0] == 'P' && magic[1] == 'K'
                    && magic[2] == 3 && magic[3] == 4;
        } catch (IOException error) {
            return false;
        }
    }

    private static String readHeader(InputStream input) throws IOException {
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        int last = 0; // the four most recent bytes, newest in the low byte
        while (bytes.size() < MAX_HEADER_BYTES) {
            int value = input.read();
            if (value < 0) {
                return null;
            }
            bytes.write(value);
            last = (last << 8) | value;
            if (last == 0x0d0a0d0a) { // "\r\n\r\n" ends the headers
                return new String(bytes.toByteArray(), StandardCharsets.ISO_8859_1);
            }
        }
        return null;
    }

    private static String headerValue(String[] lines, String name) {
        for (int i = 1; i < lines.length; ++i) {
            int colon = lines[i].indexOf(':');
            if (colon > 0 && lines[i].substring(0, colon).trim().equalsIgnoreCase(name)) {
                return lines[i].substring(colon + 1).trim();
            }
        }
        return null;
    }

    private static boolean constantTimeEquals(String expected, String supplied) {
        if (supplied == null) {
            return false;
        }
        return MessageDigest.isEqual(
                expected.getBytes(StandardCharsets.UTF_8),
                supplied.trim().getBytes(StandardCharsets.UTF_8));
    }

    private static void respondJson(OutputStream output, int status, boolean ok, String message)
            throws IOException {
        String escaped = message.replace("\\", "\\\\").replace("\"", "\\\"");
        respond(output, status, "application/json",
                "{\"ok\":" + ok + ",\"message\":\"" + escaped + "\"}");
    }

    private static void respond(OutputStream output, int status, String type, String body)
            throws IOException {
        byte[] content = body.getBytes(StandardCharsets.UTF_8);
        String reason = status == 200 ? "OK" : status == 404 ? "Not Found" : "Error";
        String head = "HTTP/1.1 " + status + " " + reason + "\r\n"
                + "Content-Type: " + type + "\r\n"
                + "Content-Length: " + content.length + "\r\n"
                + "Cache-Control: no-store\r\n"
                + "X-Content-Type-Options: nosniff\r\n"
                + "Connection: close\r\n\r\n";
        output.write(head.getBytes(StandardCharsets.ISO_8859_1));
        output.write(content);
        output.flush();
    }

    private static final String UPLOAD_PAGE = "<!doctype html>\n"
            + "<html lang=\"en\"><head><meta charset=\"utf-8\">"
            + "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">"
            + "<title>Send to Barony</title><style>"
            + "body{font-family:system-ui,sans-serif;background:#17131e;color:#f2e6d0;"
            + "margin:0;display:flex;justify-content:center;padding:32px 16px}"
            + "main{max-width:520px;width:100%}h1{font-size:1.6rem;margin:0 0 8px}"
            + "p{color:#c9b89a;line-height:1.5}label{display:block;margin:20px 0 6px;font-weight:600}"
            + "input{font-size:1rem;width:100%;box-sizing:border-box;padding:10px;"
            + "border-radius:8px;border:1px solid #5a4a63;background:#231c2c;color:#f2e6d0}"
            + "button{margin-top:24px;font-size:1.05rem;padding:12px 20px;border:0;"
            + "border-radius:8px;background:#e0763a;color:#17131e;font-weight:700;cursor:pointer}"
            + "button:disabled{opacity:.5;cursor:default}progress{width:100%;height:14px;margin-top:20px}"
            + "#status{margin-top:12px;min-height:1.5em}</style></head><body><main>"
            + "<h1>Send to Barony Android Port</h1>"
            + "<p>Choose a game-data, mod, or save ZIP made with the archive builder. "
            + "Keep the Receive from PC screen open on the TV until the transfer finishes.</p>"
            + "<label for=\"code\">Code shown on the TV</label>"
            + "<input id=\"code\" inputmode=\"numeric\" autocomplete=\"off\" maxlength=\"6\">"
            + "<label for=\"file\">ZIP file</label><input id=\"file\" type=\"file\" accept=\".zip\">"
            + "<button id=\"send\">Send</button><progress id=\"bar\" max=\"100\" value=\"0\" hidden></progress>"
            + "<div id=\"status\" role=\"status\"></div></main><script>"
            + "const send=document.getElementById('send'),bar=document.getElementById('bar'),"
            + "status=document.getElementById('status');"
            + "send.onclick=()=>{const f=document.getElementById('file').files[0];"
            + "const code=document.getElementById('code').value.trim();"
            + "if(!/^\\d{6}$/.test(code)){status.textContent='Enter the 6-digit code from the TV.';return;}"
            + "if(!f){status.textContent='Choose a ZIP file first.';return;}"
            + "const x=new XMLHttpRequest();x.open('POST','/upload');"
            + "x.setRequestHeader('X-Barony-Code',code);"
            + "x.setRequestHeader('X-Barony-Filename',encodeURIComponent(f.name));"
            + "x.upload.onprogress=e=>{if(e.lengthComputable){bar.hidden=false;"
            + "bar.value=Math.round(e.loaded*100/e.total);"
            + "status.textContent='Sending… '+bar.value+'%';}};"
            + "x.onload=()=>{let r;try{r=JSON.parse(x.responseText);}catch(e){r={message:'Unexpected reply.'};}"
            + "status.textContent=r.message;send.disabled=!!r.ok;};"
            + "x.onerror=()=>{status.textContent='The connection was lost. Is the TV screen still open?';"
            + "send.disabled=false;};send.disabled=true;status.textContent='Sending…';x.send(f);};"
            + "</script></body></html>\n";
}
