use url::Url;

pub(crate) const DEFAULT_SLINGSHOT_BASE_URL: &str = "https://chatgpt.com/backend-api";

#[derive(Clone, Debug, PartialEq, Eq)]
pub(crate) struct SlingshotConnectionUrl {
    pub environment_id: String,
    pub base_url: String,
}

pub(crate) fn is_slingshot_connection_url(raw_url: &str) -> bool {
    raw_url
        .trim_start()
        .get(..10)
        .is_some_and(|prefix| prefix.eq_ignore_ascii_case("slingshot:"))
}

pub(crate) fn parse_slingshot_connection_url(raw_url: &str) -> Option<SlingshotConnectionUrl> {
    let url = Url::parse(raw_url.trim()).ok()?;
    if url.scheme() != "slingshot" {
        return None;
    }
    let environment_id = url.host_str()?.trim().to_string();
    if environment_id.is_empty() {
        return None;
    }
    let base_url = url
        .query_pairs()
        .find_map(|(key, value)| {
            (key == "baseUrl")
                .then(|| value.trim().to_string())
                .filter(|value| !value.is_empty())
        })
        .unwrap_or_else(|| DEFAULT_SLINGSHOT_BASE_URL.to_string());
    Some(SlingshotConnectionUrl {
        environment_id,
        base_url: normalize_slingshot_base_url(&base_url),
    })
}

pub(crate) fn build_slingshot_connection_url(
    environment_id: &str,
    base_url: &str,
) -> Option<String> {
    let environment_id = environment_id.trim();
    if environment_id.is_empty() {
        return None;
    }
    let mut url = Url::parse(&format!("slingshot://{environment_id}")).ok()?;
    let base_url = normalize_slingshot_base_url(base_url);
    url.query_pairs_mut().append_pair("baseUrl", &base_url);
    Some(url.to_string())
}

pub(crate) fn normalize_slingshot_base_url(raw_url: &str) -> String {
    let Ok(mut url) = Url::parse(raw_url.trim()) else {
        return raw_url.to_string();
    };
    let host = url.host_str().unwrap_or_default();
    let path = url.path().trim_matches('/');
    if path.is_empty() && matches!(host, "chatgpt.com" | "ios.chat.openai.com") {
        url.set_path("backend-api");
    }
    url.to_string()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_normalizes_chatgpt_root_base_url() {
        let parsed =
            parse_slingshot_connection_url("slingshot://env_123?baseUrl=https://chatgpt.com")
                .expect("valid slingshot URL");

        assert_eq!(parsed.environment_id, "env_123");
        assert_eq!(parsed.base_url, DEFAULT_SLINGSHOT_BASE_URL);
    }

    #[test]
    fn build_roundtrips_environment_and_base_url() {
        let raw = build_slingshot_connection_url("env_abc", "https://chatgpt.com")
            .expect("valid marker URL");
        let parsed = parse_slingshot_connection_url(&raw).expect("roundtrip marker URL");

        assert_eq!(parsed.environment_id, "env_abc");
        assert_eq!(parsed.base_url, DEFAULT_SLINGSHOT_BASE_URL);
    }
}
