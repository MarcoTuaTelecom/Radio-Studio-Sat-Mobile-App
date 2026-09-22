//! Modelos compartilhados da plataforma Studio Sat Native V2.
//!
//! Este crate não conhece FFmpeg, HLS.js, Media3 ou AVPlayer. Ele representa
//! apenas dados e contratos. Essa separação evita que regras de negócio
//! alterem acidentalmente o caminho de mídia.

use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Station {
    pub id: String,
    pub name: String,
    pub tagline: String,
    pub stream_url: String,
    pub logo_url: Option<String>,
    pub enabled: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NowPlaying {
    pub station_id: String,
    pub title: String,
    pub artist: String,
    pub album: Option<String>,
    pub artwork_url: Option<String>,
    pub started_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct ScheduleItem {
    pub station_id: String,
    pub start: String,
    pub end: String,
    pub title: String,
    pub presenter: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct NewsItem {
    pub id: String,
    pub title: String,
    pub summary: String,
    pub url: Option<String>,
    pub published_at: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Promotion {
    pub id: String,
    pub title: String,
    pub description: String,
    pub image_url: Option<String>,
    pub active: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
pub struct Health {
    pub status: String,
    pub version: String,
}
