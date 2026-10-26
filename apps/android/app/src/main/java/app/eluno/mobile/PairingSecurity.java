package app.eluno.mobile;

import java.net.URI;
import java.security.MessageDigest;
import java.security.cert.CertificateException;
import java.security.cert.X509Certificate;
import java.util.Locale;
import javax.net.ssl.X509TrustManager;

public final class PairingSecurity {
    private PairingSecurity() {}
    public static String endpoint(String value) {
        URI uri = URI.create(value);
        String host = uri.getHost();
        if (!"https".equals(uri.getScheme()) || host == null || uri.getRawUserInfo() != null || uri.getQuery() != null || uri.getFragment() != null || !(uri.getPath().isEmpty() || uri.getPath().equals("/")) || uri.getPort() < 1 || uri.getPort() > 65535) throw new IllegalArgumentException("This is not a valid Eluno invitation.");
        String[] parts = host.split("\\.");
        if (parts.length != 4) throw new IllegalArgumentException("Use an invitation from your local computer.");
        int[] ip = new int[4];
        for (int i=0;i<4;i++) { if (!parts[i].matches("0|[1-9][0-9]{0,2}")) throw new IllegalArgumentException("Invalid local address."); ip[i] = Integer.parseInt(parts[i]); if (ip[i]>255) throw new IllegalArgumentException("Invalid local address."); }
        if (!(ip[0]==10 || (ip[0]==192 && ip[1]==168) || (ip[0]==172 && ip[1]>=16 && ip[1]<=31))) throw new IllegalArgumentException("Eluno connects to computers on your local network.");
        return "https://" + host + ":" + uri.getPort();
    }
    public static byte[] fingerprint(String value) {
        if (value == null || !value.matches("[0-9a-fA-F]{64}")) throw new IllegalArgumentException("The invitation is missing its security identity.");
        byte[] bytes = new byte[32];
        for (int i=0;i<32;i++) bytes[i] = (byte)Integer.parseInt(value.substring(i*2,i*2+2),16);
        return bytes;
    }
    public static X509TrustManager trust(String pin) {
        byte[] expected = fingerprint(pin);
        return new X509TrustManager() {
            public X509Certificate[] getAcceptedIssuers() { return new X509Certificate[0]; }
            public void checkClientTrusted(X509Certificate[] chain, String type) throws CertificateException { throw new CertificateException("Client certificates are not supported."); }
            public void checkServerTrusted(X509Certificate[] chain, String type) throws CertificateException {
                if (chain == null || chain.length == 0) throw new CertificateException("Missing computer identity.");
                chain[0].checkValidity();
                try { if (!MessageDigest.isEqual(expected, MessageDigest.getInstance("SHA-256").digest(chain[0].getEncoded()))) throw new CertificateException("This computer's identity changed. Scan its invitation again."); }
                catch (java.security.NoSuchAlgorithmException error) { throw new CertificateException(error); }
            }
        };
    }
}
