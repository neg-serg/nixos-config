//! Shadertoy API response handling.
//!
//! The shell fetched the JSON with curl, checked `jq -e '.Shader.renderpass'`
//! (any value except `null`/`false` passed), then extracted
//! `[.Shader.renderpass[] | select(.type == "image")][0].code // empty` with
//! `jq -r`. A missing code therefore produced an empty response, which the
//! caller reported as "the API returned no Image pass".

use serde_json::Value;

#[derive(Debug, PartialEq, Eq)]
pub enum ApiResponse {
    /// `jq -r` output: the code plus the newline `jq -r` adds.
    Code(Vec<u8>),
    /// No `Shader.renderpass` value: challenge page, wrong key or unknown id.
    NoShaderData,
    /// Renderpass data exists but holds no Image pass (or no code).
    NoImagePass,
}

pub fn image_pass(body: &[u8]) -> ApiResponse {
    let Ok(root) = serde_json::from_slice::<Value>(body) else {
        return ApiResponse::NoShaderData;
    };
    let Some(renderpass) = root
        .get("Shader")
        .and_then(|shader| shader.get("renderpass"))
    else {
        return ApiResponse::NoShaderData;
    };
    match renderpass {
        // `jq -e` treats only null and false as failure.
        Value::Null | Value::Bool(false) => return ApiResponse::NoShaderData,
        _ => {}
    }
    let Value::Array(passes) = renderpass else {
        return ApiResponse::NoImagePass;
    };
    let Some(pass) = passes
        .iter()
        .find(|pass| pass.get("type").and_then(Value::as_str) == Some("image"))
    else {
        return ApiResponse::NoImagePass;
    };
    match pass.get("code") {
        None | Some(Value::Null) | Some(Value::Bool(false)) => ApiResponse::NoImagePass,
        Some(Value::String(code)) => {
            let mut bytes = code.as_bytes().to_vec();
            bytes.push(b'\n');
            ApiResponse::Code(bytes)
        }
        Some(other) => {
            // `jq -r` prints scalars and compact JSON for objects/arrays.
            let mut text = serde_json::to_string(other).unwrap_or_default();
            text.push('\n');
            ApiResponse::Code(text.into_bytes())
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{image_pass, ApiResponse};

    fn code(response: ApiResponse) -> Vec<u8> {
        match response {
            ApiResponse::Code(bytes) => bytes,
            other => panic!("expected a code, got {other:?}"),
        }
    }

    #[test]
    fn extracts_the_first_image_pass() {
        let body = br#"{
            "Shader": {
                "renderpass": [
                    {"type": "common", "code": "shared"},
                    {"type": "image", "code": "void mainImage(){}"},
                    {"type": "image", "code": "second"}
                ]
            }
        }"#;
        assert_eq!(code(image_pass(body)), b"void mainImage(){}\n");
    }

    #[test]
    fn missing_or_untruthy_renderpass_is_no_shader_data() {
        assert_eq!(image_pass(br#"{"Shader": {}}"#), ApiResponse::NoShaderData);
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": null}}"#),
            ApiResponse::NoShaderData
        );
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": false}}"#),
            ApiResponse::NoShaderData
        );
        assert_eq!(image_pass(br#"not json"#), ApiResponse::NoShaderData);
        assert_eq!(
            image_pass(br#"{"error": "challenge"}"#),
            ApiResponse::NoShaderData
        );
    }

    #[test]
    fn renderpass_without_an_image_pass_is_reported() {
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": [{"type": "common", "code": "x"}]}}"#),
            ApiResponse::NoImagePass
        );
    }

    #[test]
    fn a_missing_code_is_no_image_pass() {
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": [{"type": "image"}]}}"#),
            ApiResponse::NoImagePass
        );
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": [{"type": "image", "code": null}]}}"#),
            ApiResponse::NoImagePass
        );
    }

    #[test]
    fn an_empty_code_string_still_produces_the_jq_newline() {
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": [{"type": "image", "code": ""}]}}"#),
            ApiResponse::Code(b"\n".to_vec())
        );
    }

    #[test]
    fn non_string_codes_are_rendered_like_jq_r() {
        assert_eq!(
            image_pass(br#"{"Shader": {"renderpass": [{"type": "image", "code": 7}]}}"#),
            ApiResponse::Code(b"7\n".to_vec())
        );
    }
}
