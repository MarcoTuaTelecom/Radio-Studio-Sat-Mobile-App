//! API da plataforma Studio Sat Native V2.
//!
//! A API transporta somente metadados. O áudio nunca passa por este processo.
//! Todos os clientes usam diretamente os endpoints HLS declarados em content.json.

use std::{env, net::SocketAddr, path::PathBuf, sync::Arc};

use axum::{
    extract::{Path, State},
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use studiosat_core::{Health, NewsItem, NowPlaying, Promotion, ScheduleItem, Station};
use tower_http::{cors::{Any, CorsLayer}, trace::TraceLayer};
use tracing::{error, info};

const VERSION: &str = env!("CARGO_PKG_VERSION");

#[derive(Debug, Clone, Serialize, Deserialize)]
struct Content {
    stations: Vec<Station>,
    now_playing: std::collections::HashMap<String, NowPlaying>,
    schedule: std::collections::HashMap<String, Vec<ScheduleItem>>,
    news: Vec<NewsItem>,
    promotions: Vec<Promotion>,
}

#[derive(Clone)]
struct AppState {
    content_path: Arc<PathBuf>,
}

#[tokio::main]
async fn main() {
    tracing_subscriber::fmt()
        .with_env_filter(
            tracing_subscriber::EnvFilter::try_from_default_env()
                .unwrap_or_else(|_| "studiosat_api=info,tower_http=info".into()),
        )
        .init();

    let bind = env::var("STUDIOSAT_BIND").unwrap_or_else(|_| "127.0.0.1:9080".into());
    let content_path = env::var("STUDIOSAT_CONTENT")
        .unwrap_or_else(|_| "./data/content.json".into());

    let state = AppState { content_path: Arc::new(PathBuf::from(content_path)) };

    let app = Router::new()
        .route("/api/v2/health", get(health))
        .route("/api/v2/stations", get(stations))
        .route("/api/v2/now-playing/{station}", get(now_playing))
        .route("/api/v2/schedule/{station}", get(schedule))
        .route("/api/v2/news", get(news))
        .route("/api/v2/promotions", get(promotions))
        .layer(CorsLayer::new().allow_origin(Any).allow_methods(Any).allow_headers(Any))
        .layer(TraceLayer::new_for_http())
        .with_state(state);

    let addr: SocketAddr = bind.parse().expect("STUDIOSAT_BIND inválido");
    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .expect("falha ao abrir socket");
    info!(%addr, "Studio Sat API V2 pronta");

    axum::serve(listener, app).await.expect("falha do servidor HTTP");
}

async fn health() -> Json<Health> {
    Json(Health { status: "ok".into(), version: VERSION.into() })
}

async fn stations(State(state): State<AppState>) -> impl IntoResponse {
    load(&state).await.map(|c| Json(c.stations)).map_err(api_error)
}

async fn now_playing(State(state): State<AppState>, Path(station): Path<String>) -> impl IntoResponse {
    match load(&state).await {
        Ok(content) => content.now_playing.get(&station).cloned()
            .map(Json)
            .ok_or_else(|| api_error(format!("estação desconhecida: {station}"))),
        Err(e) => Err(api_error(e)),
    }
}

async fn schedule(State(state): State<AppState>, Path(station): Path<String>) -> impl IntoResponse {
    match load(&state).await {
        Ok(content) => content.schedule.get(&station).cloned()
            .map(Json)
            .ok_or_else(|| api_error(format!("estação desconhecida: {station}"))),
        Err(e) => Err(api_error(e)),
    }
}

async fn news(State(state): State<AppState>) -> impl IntoResponse {
    load(&state).await.map(|c| Json(c.news)).map_err(api_error)
}

async fn promotions(State(state): State<AppState>) -> impl IntoResponse {
    load(&state).await.map(|c| Json(c.promotions)).map_err(api_error)
}

async fn load(state: &AppState) -> Result<Content, String> {
    let raw = tokio::fs::read_to_string(&*state.content_path)
        .await
        .map_err(|e| format!("{}: {e}", state.content_path.display()))?;
    serde_json::from_str(&raw)
        .map_err(|e| format!("{}: {e}", state.content_path.display()))
}

fn api_error(message: String) -> (StatusCode, Json<Value>) {
    error!(%message, "erro da API");
    (StatusCode::INTERNAL_SERVER_ERROR, Json(json!({"error":"data_error","detail":message})))
}
