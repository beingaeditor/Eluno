package app.eluno.mobile;

import org.json.JSONObject;
import java.io.IOException;
import java.util.concurrent.TimeUnit;
import javax.net.ssl.SSLContext;
import javax.net.ssl.X509TrustManager;
import okhttp3.*;

public final class ElunoApi {
    public static final class ApiException extends IOException {
        public final int status;
        ApiException(int status, String message) { super(message); this.status = status; }
    }
    public final String origin;
    public final OkHttpClient http;
    public volatile String token, deviceId;
    public ElunoApi(String endpoint, String pin) throws Exception {
        origin = PairingSecurity.endpoint(endpoint);
        X509TrustManager trust = PairingSecurity.trust(pin);
        SSLContext tls = SSLContext.getInstance("TLS"); tls.init(null, new X509TrustManager[]{trust}, null);
        String expectedHost = java.net.URI.create(origin).getHost();
        http = new OkHttpClient.Builder().sslSocketFactory(tls.getSocketFactory(), trust)
            .hostnameVerifier((host, session) -> {
                if (!host.equals(expectedHost)) return false;
                try { trust.checkServerTrusted(new java.security.cert.X509Certificate[]{(java.security.cert.X509Certificate)session.getPeerCertificates()[0]}, "RSA"); return true; }
                catch (Exception e) { return false; }
            }).followRedirects(false).followSslRedirects(false).connectTimeout(4, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).build();
    }
    public Request.Builder request(String route) {
        if (!route.startsWith("/") || route.startsWith("//")) throw new IllegalArgumentException("Invalid request.");
        Request.Builder builder = new Request.Builder().url(origin + route);
        if (token != null) builder.header("Authorization", "Bearer " + token);
        return builder;
    }
    public JSONObject json(String method, String route, JSONObject data) throws Exception {
        RequestBody body = method.equals("GET") ? null : RequestBody.create(data == null ? "{}" : data.toString(), MediaType.get("application/json"));
        try (Response response = http.newCall(request(route).method(method, body).build()).execute()) {
            String text = response.body() == null ? "{}" : response.body().string();
            JSONObject result = new JSONObject(text);
            if (!response.isSuccessful()) throw new ApiException(response.code(), result.optString("error", "Connection interrupted. Try again."));
            return result;
        }
    }
    public void chunk(String id, byte[] bytes) throws Exception {
        try (Response response = http.newCall(request("/api/chunks/" + id).post(RequestBody.create(bytes, MediaType.get("application/octet-stream"))).build()).execute()) {
            if (!response.isSuccessful() && response.code()!=410) throw new IOException("File sharing was interrupted.");
        }
    }
    public void close() { http.dispatcher().cancelAll(); http.connectionPool().evictAll(); }
}
