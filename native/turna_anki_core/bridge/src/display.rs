//! Display-time IRI encoding. Raw HTML stays unencoded; UI only shows this.

use anki::text::encode_iri_paths;
use regex::Regex;


static CSS_URL: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
    Regex::new(r#"(?xi)url\(\s*(?:'([^']*)'|"([^"]*)"|([^)]+?))\s*\)"#).unwrap()
});

static SCRIPT_SRC: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
    Regex::new(
        r#"(?xsi)
        <script\b
        (?:
            [^>]
            |
            "[^"]*?"
            |
            '[^']*?'
        )+?
        \bsrc\s*=
        (?:
            "([^"]+?)"
            |
            '([^']+?)'
            |
            ([^ >]+?)
        )
        "#,
    )
    .unwrap()
});

static HTML_LOCAL_REF: std::sync::LazyLock<Regex> = std::sync::LazyLock::new(|| {
    Regex::new(
        r#"(?xsi)
        <\b(?:img|audio|video|object|source|script)\b
        (?:
            [^>]
            |
            "[^"]*?"
            |
            '[^']*?'
        )+?
        \b(?:src|data)\b\s*=
        (?:
            "([^"]+?)"
            |
            '([^']+?)'
            |
            ([^ >]+?)
        )
        "#,
    )
    .unwrap()
});

fn is_remote(name: &str) -> bool {
    let trimmed = name.trim();
    trimmed.get(..7).is_some_and(|s| s.eq_ignore_ascii_case("http://"))
        || trimmed
            .get(..8)
            .is_some_and(|s| s.eq_ignore_ascii_case("https://"))
}

fn capture_name<'a>(caps: &regex::Captures<'a>) -> &'a str {
    caps.get(1)
        .or_else(|| caps.get(2))
        .or_else(|| caps.get(3))
        .map(|m| m.as_str())
        .unwrap_or("")
}

/// Protect `%` and `?` so one URL decode restores the Collection filename.
fn protect_specials(name: &str) -> String {
    name.replace('%', "%25").replace('?', "%3F")
}

fn encode_local_filename(name: &str) -> String {
    if name.is_empty() || is_remote(name) {
        return name.to_string();
    }
    let protected = protect_specials(name);
    let wrapped = format!("<img src=\"{protected}\">");
    let encoded = encode_iri_paths(&wrapped);
    extract_img_src(&encoded).unwrap_or(protected)
}

fn extract_img_src(html: &str) -> Option<String> {
    let start = html.find("src=\"")? + 5;
    let rest = &html[start..];
    let end = rest.find('"')?;
    Some(rest[..end].to_string())
}

fn rewrite_captured(full: &str, original: &str, encoded: &str) -> String {
    if original == encoded {
        full.to_string()
    } else {
        full.replacen(original, encoded, 1)
    }
}

/// Official `encode_iri_paths` plus `%`/`?` protection and script src.
pub fn encode_display_html(html: &str) -> String {
    let protected = HTML_LOCAL_REF.replace_all(html, |caps: &regex::Captures| {
        let name = capture_name(caps);
        if is_remote(name) {
            return caps.get(0).unwrap().as_str().to_string();
        }
        rewrite_captured(caps.get(0).unwrap().as_str(), name, &protect_specials(name))
    });
    let official = encode_iri_paths(&protected);
    let with_scripts = SCRIPT_SRC.replace_all(&official, |caps: &regex::Captures| {
        let name = capture_name(caps);
        let encoded = encode_local_filename(name);
        rewrite_captured(caps.get(0).unwrap().as_str(), name, &encoded)
    });
    with_scripts.into_owned()
}

/// Encode local `url(...)` in notetype CSS. Does not treat the stylesheet as HTML.
pub fn encode_display_css(css: &str) -> String {
    CSS_URL
        .replace_all(css, |caps: &regex::Captures| {
            let name = capture_name(caps).trim();
            if name.is_empty() || is_remote(name) {
                return caps.get(0).unwrap().as_str().to_string();
            }
            let encoded = encode_local_filename(name);
            let full = caps.get(0).unwrap().as_str();
            if let Some(q) = full.chars().find(|c| *c == '"' || *c == '\'') {
                format!("url({q}{encoded}{q})")
            } else {
                format!("url({encoded})")
            }
        })
        .into_owned()
}

pub fn body_class_for_ordinal(template_ordinal: u16) -> String {
    format!("card card{}", template_ordinal + 1)
}



#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn official_encode_handles_space_and_hash() {
        assert_eq!(
            encode_iri_paths("<img src=\"hello world.png\">").as_ref(),
            "<img src=\"hello%20world.png\">"
        );
        assert_eq!(
            encode_iri_paths("<img src=\"hash#tag.png\">").as_ref(),
            "<img src=\"hash%23tag.png\">"
        );
    }

    #[test]
    fn display_html_encodes_space_unicode_hash_query_percent_and_dotdot_name() {
        let raw = concat!(
            r#"<img src="hello world.png">"#,
            r#"<img src="中文图片.jpg">"#,
            r#"<img src="hash#tag.png">"#,
            r#"<img src="question?.png">"#,
            r#"<img src="percent%20literal.png">"#,
            r#"<img src="foo..bar.png">"#,
            r#"<audio src="paren (1).mp3"></audio>"#,
            r#"<script src="local library.js"></script>"#,
        );
        let encoded = encode_display_html(raw);
        assert!(encoded.contains("hello%20world.png"), "{encoded}");
        assert!(encoded.contains("中文图片.jpg"), "{encoded}");
        assert!(encoded.contains("hash%23tag.png"), "{encoded}");
        assert!(encoded.contains("question%3F.png"), "{encoded}");
        assert!(encoded.contains("percent%2520literal.png"), "{encoded}");
        assert!(encoded.contains("foo..bar.png"), "{encoded}");
        assert!(encoded.contains("paren%20(1).mp3"), "{encoded}");
        assert!(encoded.contains("local%20library.js"), "{encoded}");
        assert!(!encoded.contains("file://"), "{encoded}");
        assert!(!encoded.contains("content://"), "{encoded}");
        assert_eq!(raw.matches("hello world.png").count(), 1);
    }

    #[test]
    fn display_keeps_raw_html_unencoded() {
        let raw = r#"<img src="hello world.png">"#;
        let display = encode_display_html(raw);
        assert_ne!(raw, display);
        assert!(raw.contains("hello world.png"));
        assert!(display.contains("hello%20world.png"));
    }

    #[test]
    fn css_url_encoder_does_not_regex_the_whole_sheet_as_html() {
        let css = ".card { background: url(hello world.png); } .x { content: '<img src=\"keep\">'; }";
        let encoded = encode_display_css(css);
        assert!(encoded.contains("hello%20world.png"), "{encoded}");
        assert!(encoded.contains("<img src=\"keep\">"), "{encoded}");
        assert!(encode_display_css("url('hash#tag.woff2')").contains("hash%23tag.woff2"));
        assert!(encode_display_css("url(\"question?.png\")").contains("question%3F.png"));
        assert!(encode_display_css("url(https://evil.example/x.png)").contains("https://evil.example/x.png"));
    }

    #[test]
    fn body_class_is_card_plus_one_based_ordinal() {
        assert_eq!(body_class_for_ordinal(0), "card card1");
        assert_eq!(body_class_for_ordinal(1), "card card2");
        assert!(!body_class_for_ordinal(0).contains("isWin"));
        assert!(!body_class_for_ordinal(0).contains("isMac"));
        assert!(!body_class_for_ordinal(0).contains("isLin"));
    }
}
