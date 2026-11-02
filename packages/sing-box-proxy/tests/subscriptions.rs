//! Subscription-fetch tests for the `fetch_sub` port.
//!
//! A scripted curl stub serves bodies from environment variables, so the test
//! covers: empty direct fetch -> retry through the running proxy, base64
//! decoding, the scheme/xhttp/plugin filters, `NODE_SAMPLE` and the fact that
//! no trailing newline is returned (command-substitution semantics).

mod common;

use base64::Engine as _;
use common::Stubs;
use sing_box_proxy::subscriptions::fetch_sub;

const BASE64_BODY_SOURCE: &str = "vless://a@h.example.com:443?security=tls&type=xhttp#drop\n\
     vless://b@h.example.com:443?security=tls#keep\n\
     ss://aes-128-gcm:pw@ss.example.com:8388?plugin=obfs-local#drop\n\
     vless://c@h.example.com:444?security=tls#keep2\n";

fn base64_body() -> String {
    base64::engine::general_purpose::STANDARD.encode(BASE64_BODY_SOURCE)
}

#[test]
fn fetch_sub_retries_decodes_and_filters() {
    let stubs = Stubs::new("subscriptions");
    stubs.add(
        "curl",
        r#"case "$*" in
  *--noproxy*) printf '%s' "$FAKE_DIRECT" ;;
  *) printf '%s' "$FAKE_PROXY" ;;
esac"#,
    );
    stubs.add("pgrep", "exit 0");
    std::env::set_var("PATH", stubs.only_path());

    // Empty direct body + running proxy -> the second request is used.
    std::env::set_var("FAKE_DIRECT", "");
    std::env::set_var(
        "FAKE_PROXY",
        "vless://node@127.0.0.1:443?security=tls#via-proxy",
    );
    assert_eq!(
        fetch_sub("https://example.test/sub"),
        "vless://node@127.0.0.1:443?security=tls#via-proxy"
    );

    // Base64 body: xhttp and plugin nodes are dropped.
    std::env::set_var("FAKE_DIRECT", base64_body());
    std::env::remove_var("NODE_SAMPLE");
    let mut lines: Vec<String> = fetch_sub("https://example.test/sub")
        .lines()
        .map(|line| line.to_string())
        .collect();
    lines.sort();
    assert_eq!(
        lines,
        vec![
            "vless://b@h.example.com:443?security=tls#keep".to_string(),
            "vless://c@h.example.com:444?security=tls#keep2".to_string(),
        ]
    );

    // NODE_SAMPLE caps the sampled list.
    std::env::set_var("NODE_SAMPLE", "1");
    let sampled = fetch_sub("https://example.test/sub");
    assert_eq!(sampled.lines().count(), 1, "{sampled}");
    assert!(!sampled.ends_with('\n'));

    // Invalid NODE_SAMPLE mimics `head -<garbage>` producing nothing.
    std::env::set_var("NODE_SAMPLE", "not-a-number");
    assert_eq!(fetch_sub("https://example.test/sub"), "");
}
