package app.eluno.mobile;
import org.junit.Test;
import static org.junit.Assert.*;
public class PairingSecurityTest {
    @Test public void allowsOnlyPrivateHttpsEndpoints(){assertEquals("https://192.168.1.20:4174",PairingSecurity.endpoint("https://192.168.1.20:4174/"));assertEquals("https://10.0.2.2:8000",PairingSecurity.endpoint("https://10.0.2.2:8000"));}
    @Test public void rejectsPublicAndAmbiguousAddresses(){for(String value:new String[]{"http://192.168.1.2:44","https://example.com:443","https://8.8.8.8:443","https://192.168.1.2:44/path","https://user@192.168.1.2:44","https://192.168.1.2:44?x=1","https://172.32.0.1:443","https://192.168.1.999:443"}){try{PairingSecurity.endpoint(value);fail(value);}catch(IllegalArgumentException expected){}}}
    @Test public void requiresExactFingerprint(){assertEquals(32,PairingSecurity.fingerprint("ab".repeat(32)).length);for(String value:new String[]{"", "abc", "xx".repeat(32)}){try{PairingSecurity.fingerprint(value);fail(value);}catch(IllegalArgumentException expected){}}}
}
