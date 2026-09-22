//! Portal Studio Sat V2 em Rust/WASM.
//!
//! O Rust controla UI, estação selecionada e metadados. A mídia em si é
//! entregue ao `HTMLAudioElement`. A pequena ponte JavaScript existe somente
//! para compatibilidade HLS/MSE em navegadores que não reproduzem HLS
//! nativamente.
//!
//! PROIBIDO neste arquivo: AudioContext, AnalyserNode, currentTime chasing,
//! playbackRate dinâmico ou DSP.

use std::{cell::RefCell, rc::Rc};

use serde::de::DeserializeOwned;
use studiosat_core::{NowPlaying, Station};
use wasm_bindgen::{closure::Closure, prelude::*, JsCast};
use wasm_bindgen_futures::{spawn_local, JsFuture};
use web_sys::{Document, Element, HtmlAudioElement, Response, Window};

#[wasm_bindgen]
extern "C" {
    #[wasm_bindgen(catch, js_namespace = StudioSatMedia, js_name = play)]
    async fn media_play(url: &str) -> Result<JsValue, JsValue>;

    #[wasm_bindgen(js_namespace = StudioSatMedia, js_name = pause)]
    fn media_pause();

    #[wasm_bindgen(js_namespace = StudioSatMedia, js_name = isPlaying)]
    fn media_is_playing() -> bool;

    #[wasm_bindgen(js_namespace = StudioSatMedia, js_name = setVolume)]
    fn media_set_volume(value: f64);
}

#[wasm_bindgen(start)]
pub async fn start() -> Result<(), JsValue> {
    console_error_panic_hook::set_once();

    let window = web_sys::window().ok_or("window ausente")?;
    let document = window.document().ok_or("document ausente")?;

    install_shell(&document)?;

    let stations: Vec<Station> = fetch_json("/api/v2/stations").await?;
    if stations.is_empty() {
        set_text(&document, "status", "Nenhuma emissora disponível")?;
        return Ok(());
    }

    let selected = Rc::new(RefCell::new(stations[0].id.clone()));
    render_stations(&document, &stations, selected.clone())?;
    install_play_button(&document, &stations, selected.clone())?;
    install_volume(&document)?;
    install_metadata_timer(&window, &document, selected.clone())?;

    select_station(&document, &stations[0]);
    refresh_now_playing(&document, &stations[0].id).await;

    Ok(())
}

fn install_shell(document: &Document) -> Result<(), JsValue> {
    let app = document
        .get_element_by_id("app")
        .ok_or("elemento #app ausente")?;

    app.set_inner_html(
        r#"
        <main class="app-shell">
          <header class="hero">
            <div>
              <div class="eyebrow">STUDIO SAT WEB</div>
              <h1>Rádio Sat</h1>
              <p id="tagline">Áudio direto. Sem processamento no cliente.</p>
            </div>
            <div id="live-pill" class="live-pill">● AO VIVO</div>
          </header>

          <section class="player-card">
            <div class="station-copy">
              <div id="station-name" class="station-name">Carregando...</div>
              <div id="now-title" class="track">Programação ao vivo</div>
              <div id="now-artist" class="artist">Studio Sat</div>
            </div>

            <div id="visualizer" class="visualizer" aria-hidden="true">
              <span></span><span></span><span></span><span></span><span></span>
              <span></span><span></span><span></span><span></span><span></span>
            </div>

            <audio id="radio-audio" preload="auto" playsinline></audio>

            <div class="controls">
              <button id="play" class="play" type="button">▶</button>
              <label class="volume">
                Volume
                <input id="volume" type="range" min="0" max="100" value="100"/>
              </label>
            </div>

            <div id="status" class="status">PRONTO</div>
          </section>

          <section>
            <h2>Emissoras</h2>
            <div id="stations" class="stations"></div>
          </section>
        </main>
        "#,
    );

    Ok(())
}

fn render_stations(
    document: &Document,
    stations: &[Station],
    selected: Rc<RefCell<String>>,
) -> Result<(), JsValue> {
    let container = document
        .get_element_by_id("stations")
        .ok_or("#stations ausente")?;
    container.set_inner_html("");

    for station in stations.iter().filter(|s| s.enabled) {
        let button = document.create_element("button")?;
        button.set_class_name("station-button");
        button.set_attribute("type", "button")?;
        button.set_attribute("data-station", &station.id)?;
        button.set_text_content(Some(&station.name));

        let station_owned = station.clone();
        let document_owned = document.clone();
        let selected_owned = selected.clone();

        let closure = Closure::<dyn FnMut(_)>::new(move |_event: web_sys::Event| {
            *selected_owned.borrow_mut() = station_owned.id.clone();
            select_station(&document_owned, &station_owned);

            let doc = document_owned.clone();
            let id = station_owned.id.clone();
            spawn_local(async move {
                refresh_now_playing(&doc, &id).await;
            });
        });

        button.add_event_listener_with_callback("click", closure.as_ref().unchecked_ref())?;
        closure.forget();
        container.append_child(&button)?;
    }

    Ok(())
}

fn install_play_button(
    document: &Document,
    stations: &[Station],
    selected: Rc<RefCell<String>>,
) -> Result<(), JsValue> {
    let button = document
        .get_element_by_id("play")
        .ok_or("#play ausente")?;
    let stations = stations.to_vec();
    let document = document.clone();

    let closure = Closure::<dyn FnMut(_)>::new(move |_event: web_sys::Event| {
        if media_is_playing() {
            media_pause();
            let _ = set_text(&document, "play", "▶");
            set_playing_visual(&document, false);
            let _ = set_text(&document, "status", "PAUSADO");
            return;
        }

        let station_id = selected.borrow().clone();
        let Some(station) = stations.iter().find(|s| s.id == station_id) else {
            return;
        };

        let url = station.stream_url.clone();
        let document_async = document.clone();

        spawn_local(async move {
            let _ = set_text(&document_async, "status", "CONECTANDO...");
            match media_play(&url).await {
                Ok(_) => {
                    let _ = set_text(&document_async, "play", "Ⅱ");
                    let _ = set_text(&document_async, "status", "AO VIVO");
                    set_playing_visual(&document_async, true);
                }
                Err(_) => {
                    let _ = set_text(&document_async, "status", "ERRO DE REPRODUÇÃO");
                    set_playing_visual(&document_async, false);
                }
            }
        });
    });

    button.add_event_listener_with_callback("click", closure.as_ref().unchecked_ref())?;
    closure.forget();
    Ok(())
}

fn install_volume(document: &Document) -> Result<(), JsValue> {
    let input = document
        .get_element_by_id("volume")
        .ok_or("#volume ausente")?;

    let closure = Closure::<dyn FnMut(_)>::new(move |event: web_sys::Event| {
        if let Some(target) = event.target() {
            if let Ok(input) = target.dyn_into::<web_sys::HtmlInputElement>() {
                let value = input.value_as_number().clamp(0.0, 100.0) / 100.0;
                media_set_volume(value);
            }
        }
    });

    input.add_event_listener_with_callback("input", closure.as_ref().unchecked_ref())?;
    closure.forget();
    Ok(())
}

fn install_metadata_timer(
    window: &Window,
    document: &Document,
    selected: Rc<RefCell<String>>,
) -> Result<(), JsValue> {
    let document = document.clone();

    let closure = Closure::<dyn FnMut()>::new(move || {
        let id = selected.borrow().clone();
        let doc = document.clone();
        spawn_local(async move {
            refresh_now_playing(&doc, &id).await;
        });
    });

    window.set_interval_with_callback_and_timeout_and_arguments_0(
        closure.as_ref().unchecked_ref(),
        10_000,
    )?;
    closure.forget();
    Ok(())
}

fn select_station(document: &Document, station: &Station) {
    let _ = set_text(document, "station-name", &station.name);
    let _ = set_text(document, "tagline", &station.tagline);

    if let Ok(nodes) = document.query_selector_all("[data-station]") {
        for i in 0..nodes.length() {
            if let Some(node) = nodes.item(i) {
                if let Ok(element) = node.dyn_into::<Element>() {
                    let active = element
                        .get_attribute("data-station")
                        .map(|v| v == station.id)
                        .unwrap_or(false);
                    let _ = element.class_list().toggle_with_force("active", active);
                }
            }
        }
    }

    // Trocar estação nunca faz seek nem aceleração. Se houver reprodução, o
    // usuário pressiona play e o bridge abre a nova URL limpa.
    if media_is_playing() {
        media_pause();
        let _ = set_text(document, "play", "▶");
        set_playing_visual(document, false);
        let _ = set_text(document, "status", "PRONTO");
    }
}

async fn refresh_now_playing(document: &Document, station: &str) {
    let url = format!("/api/v2/now-playing/{station}");
    if let Ok(data) = fetch_json::<NowPlaying>(&url).await {
        let _ = set_text(document, "now-title", &data.title);
        let _ = set_text(document, "now-artist", &data.artist);
    }
}

async fn fetch_json<T: DeserializeOwned>(url: &str) -> Result<T, JsValue> {
    let window = web_sys::window().ok_or("window ausente")?;
    let response = JsFuture::from(window.fetch_with_str(url)).await?;
    let response: Response = response.dyn_into()?;

    if !response.ok() {
        return Err(JsValue::from_str(&format!(
            "HTTP {} em {}",
            response.status(),
            url
        )));
    }

    let text = JsFuture::from(response.text()?).await?;
    let text = text.as_string().ok_or("resposta não textual")?;
    serde_json::from_str(&text).map_err(|e| JsValue::from_str(&e.to_string()))
}

fn set_text(document: &Document, id: &str, value: &str) -> Result<(), JsValue> {
    let element = document
        .get_element_by_id(id)
        .ok_or_else(|| JsValue::from_str(&format!("#{id} ausente")))?;
    element.set_text_content(Some(value));
    Ok(())
}

fn set_playing_visual(document: &Document, playing: bool) {
    if let Some(element) = document.get_element_by_id("visualizer") {
        let _ = element.class_list().toggle_with_force("playing", playing);
    }
}
