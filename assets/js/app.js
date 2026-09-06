(() => {
  const state = {
    basePath: document.body.dataset.basePath || "",
    tracksUrl: document.body.dataset.tracksUrl || "data/tracks.json",
    registryUrl: document.body.dataset.registryUrl || "data/cc0-registry.json",
  };

  const formatTime = (seconds) => {
    if (!Number.isFinite(seconds)) return "0:00";
    const minutes = Math.floor(seconds / 60);
    const rest = Math.floor(seconds % 60).toString().padStart(2, "0");
    return `${minutes}:${rest}`;
  };

  const resolveAsset = (path) => `${state.basePath}${path}`;

  const escapeHtml = (value = "") =>
    String(value).replace(/[&<>"']/g, (char) => ({
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    }[char]));

  const trackSlug = (track) => track.slug || track.id;

  const previewPath = (track) => track.preview || track.mp3;

  const fullMixPath = (track) => track.full_mix || track.wav;

  const trackUrl = (track) => `${state.basePath}tracks/?id=${encodeURIComponent(trackSlug(track))}`;

  const verifyUrl = (itemId = "") => `${state.basePath}verify.html${itemId ? `#${encodeURIComponent(itemId)}` : ""}`;

  const metaLine = (track) =>
    [track.bpm ? `${track.bpm} BPM` : "", track.key, track.duration].filter(Boolean).map((item) => `<span>${escapeHtml(item)}</span>`).join("");

  const formatDate = (value = "") => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) return value;
    const [year, month, day] = value.split("-");
    return `${day}.${month}.${year}`;
  };

  const itemVersions = (item = {}) => {
    if (Array.isArray(item.versions) && item.versions.length) {
      return [...item.versions].sort((a, b) => Number(b.version || 0) - Number(a.version || 0));
    }
    return [{
      version: item.current_version || 1,
      release_date: item.release_date,
      note: null,
      files: item.files || [],
    }];
  };

  const currentVersion = (item = {}) => {
    const versions = itemVersions(item);
    const explicit = Number(item.current_version || 0);
    return versions.find((version) => Number(version.version) === explicit) || versions[0];
  };

  const playerMarkup = (track) => {
    const preview = previewPath(track);
    if (!preview) {
      return `<p class="load-state">MP3 для прослуховування ще не додано.</p>`;
    }

    return `
      <div class="track-player" data-player>
        <button class="play-button" type="button" data-play aria-label="Відтворити ${escapeHtml(track.title)}">▶</button>
        <div class="player-timeline">
          <input class="seek" type="range" min="0" max="100" value="0" step="0.1" data-seek aria-label="Позиція відтворення ${escapeHtml(track.title)}">
        </div>
        <time class="player-time" data-time>0:00</time>
        <audio preload="metadata" data-audio>
          <source src="${resolveAsset(preview)}" type="audio/mpeg">
        </audio>
      </div>
    `;
  };

  const downloadMarkup = (track) => {
    const stems = track.stems;
    const preview = previewPath(track);
    const fullMix = fullMixPath(track);

    return `
      <div class="download-actions compact" aria-label="Завантажити трек ${escapeHtml(track.title)}">
        ${stems ? `
          <span class="primary-download">
            <a class="button" href="${resolveAsset(stems)}" download>Завантажити STEMS</a>
            <small>ZIP · окремі доріжки</small>
          </span>
        ` : ""}
        ${preview ? `<a class="button secondary" href="${resolveAsset(preview)}" download>MP3 preview</a>` : ""}
        ${fullMix ? `<a class="button secondary" href="${resolveAsset(fullMix)}" download>Повний мікс</a>` : ""}
      </div>
    `;
  };

  const formatHash = (hash) => hash ? `<code>${escapeHtml(hash)}</code>` : `<span class="pending">ще не опубліковано</span>`;

  const allRegistryItems = (registry = []) =>
    registry.flatMap((entry) => entry.items.map((item) => ({ ...item, registry: entry.registry, release_date: entry.release_date, declaration_status: entry.declaration_status })));

  const findRegistryItem = (track, registry) =>
    allRegistryItems(registry).find((item) => item.id === (track.cc0_item_id || track.id));

  const provenanceMarkup = (track, registryItem) => {
    if (!registryItem) {
      return `
        <section class="provenance-block">
          <h2>Перевірка CC0</h2>
          <p>Для цього треку ще не знайдено запис у публічному реєстрі CC0.</p>
          <a class="text-button primary-link" href="${verifyUrl()}">Перевірити CC0 →</a>
        </section>
      `;
    }

    const version = currentVersion(registryItem);
    const fileRows = (version.files || []).map((file) => fileRowMarkup(file)).join("");

    return `
      <section class="provenance-block" id="${escapeHtml(registryItem.id)}">
        <h2>Перевірка CC0</h2>
        <p><strong>CC0 1.0 Universal</strong></p>
        <p>Безкоштовно для будь-якого використання. Дозвіл, роялті та атрибуція не потрібні.</p>
        <dl class="source-list compact">
          <div>
            <dt>ID</dt>
            <dd><code>${escapeHtml(registryItem.id)}</code></dd>
          </div>
          <div>
            <dt>Версія</dt>
            <dd>${escapeHtml(version.version || registryItem.current_version || track.current_version || 1)}</dd>
          </div>
          <div>
            <dt>Реєстр CC0</dt>
            <dd>№${escapeHtml(registryItem.registry)}</dd>
          </div>
          <div>
            <dt>Походження</dt>
            <dd>${escapeHtml(registryItem.origin_label)}</dd>
          </div>
        </dl>
        <ul class="file-list">${fileRows}</ul>
        <a class="text-button primary-link" href="${verifyUrl(registryItem.id)}">Перевірити CC0 →</a>
      </section>
    `;
  };

  const trackRowMarkup = (track) => `
    <article class="track-row">
      <a class="track-thumb" href="${trackUrl(track)}" aria-label="Відкрити сторінку треку ${escapeHtml(track.title)}">
        <img src="${resolveAsset(track.cover || "assets/images/site-artwork.jpg")}" alt="">
      </a>
      <div class="track-info">
        <h3><a href="${trackUrl(track)}">${escapeHtml(track.title)}</a></h3>
        <p class="track-meta-line">${metaLine(track)}</p>
      </div>
      ${playerMarkup(track)}
      <div class="track-license">
        <span class="cc0-pill">${escapeHtml(track.license || "CC0")}</span>
        <small>Вільне використання.<br>Без обов’язкової атрибуції.</small>
      </div>
      ${downloadMarkup(track)}
    </article>
  `;

  const detailMarkup = (track, registryItem) => `
    <header class="track-hero">
      <div class="release-layout">
        <img class="release-cover" src="${resolveAsset(track.cover || "assets/images/site-artwork.jpg")}" alt="Обкладинка треку ${escapeHtml(track.title)}">
        <div class="release-main">
          <p class="eyebrow">СТОРІНКА ТРЕКУ</p>
          <h1>${escapeHtml(track.title)}</h1>
          <p class="version-line">Версія ${escapeHtml(track.current_version || 1)}</p>
          ${playerMarkup(track)}
          <p class="track-meta-line">${metaLine(track)}</p>
          ${track.updated && track.updated !== track.published ? `<p class="updated-line">Оновлено: ${escapeHtml(formatDate(track.updated))}</p>` : ""}
          <p class="license-line">CC0 · Вільне використання · Без обов’язкової атрибуції</p>
          ${downloadMarkup(track)}
        </div>
      </div>
    </header>

    <section class="content-section">
      <h2>Про трек</h2>
      <p>${escapeHtml(track.description)}</p>
    </section>

    <section class="content-section">
      <h2>Ліцензія</h2>
      <p>Трек опубліковано під CC0 1.0 Universal. Його можна використовувати, змінювати, семплувати, випускати й монетизувати без дозволу та без обов’язкової атрибуції.</p>
      <ul class="permission-list" aria-label="Дозволене використання">
        <li>Комерційне використання</li>
        <li>Монетизація</li>
        <li>Без обов’язкової атрибуції</li>
        <li>Зміни й семплування</li>
        <li>Неексклюзивно</li>
      </ul>
    </section>

    ${provenanceMarkup(track, registryItem)}

    <section class="content-section notice">
      <h2>Неексклюзивний реліз</h2>
      <p>Цей трек може використовувати будь-хто. Використання треку не надає ексклюзивних прав на оригінальний матеріал.</p>
    </section>

    <section class="content-section">
      <h2>Технічна інформація</h2>
      <dl class="source-list">
        <div>
          <dt>Походження інструменталу</dt>
          <dd>${escapeHtml(registryItem?.origin_label || track.origin_note || (track.suno_generated ? "Частина матеріалу створена за допомогою Suno." : "Не вказано"))}</dd>
        </div>
        <div>
          <dt>Публікація</dt>
          <dd>Опубліковано під <a href="https://creativecommons.org/publicdomain/zero/1.0/" rel="license noopener">CC0 1.0 Universal</a></dd>
        </div>
        <div>
          <dt>Дата</dt>
          <dd><time datetime="${escapeHtml(track.published)}">${escapeHtml(track.published)}</time></dd>
        </div>
        <div>
          <dt>Ідентифікатор</dt>
          <dd><code>${escapeHtml(track.cc0_item_id || track.id)}</code></dd>
        </div>
      </dl>
    </section>
  `;

  const registryItemMarkup = (item, registry) => {
    const versions = itemVersions({ ...item, release_date: item.release_date || registry.release_date });

    const statement = item.type === "original_lyrics"
      ? `<p>${escapeHtml(item.author_declaration || "Заявлено як оригінальний текст, створений видавцем проєкту.")}</p>`
      : `<p>${escapeHtml(item.origin_label || "Походження не вказано")}</p>`;

    return `
      <article class="registry-item" id="${escapeHtml(item.id)}">
        <div>
          <p class="eyebrow"><code>${escapeHtml(item.id)}</code></p>
          <h3>${escapeHtml(item.title)}</h3>
          ${statement}
        </div>
        <dl class="source-list compact">
          <div>
            <dt>Тип</dt>
            <dd>${escapeHtml(item.type)}</dd>
          </div>
          <div>
            <dt>Реєстр</dt>
            <dd>№${escapeHtml(registry.registry)}</dd>
          </div>
          <div>
            <dt>Поточна версія</dt>
            <dd>${escapeHtml(item.current_version || versions[0]?.version || 1)}</dd>
          </div>
          <div>
            <dt>Походження</dt>
            <dd>${escapeHtml(item.origin_label || "Не вказано")}</dd>
          </div>
        </dl>
        <div class="version-history">
          ${versions.map((version) => `
            <section class="version-entry">
              <h4>Version ${escapeHtml(version.version || 1)}</h4>
              <p>${escapeHtml(formatDate(version.release_date || registry.release_date || ""))}</p>
              ${version.note ? `<p>${escapeHtml(version.note)}</p>` : ""}
              <ul class="file-list">${(version.files || []).map((file) => fileRowMarkup(file)).join("")}</ul>
            </section>
          `).join("")}
        </div>
        ${item.public_url ? `<a class="text-button primary-link" href="${resolveAsset(item.public_url)}">Відкрити матеріал →</a>` : ""}
      </article>
    `;
  };

  const fileRowMarkup = (file) => {
    const contents = Array.isArray(file.contents) && file.contents.length
      ? `
        <details class="archive-contents">
          <summary>Вміст архіву</summary>
          <ul>
            ${file.contents.map((entry) => `
              <li>
                <span>${escapeHtml(entry.file)}</span>
                ${entry.format ? `<em>${escapeHtml(entry.format)}</em>` : ""}
                <small>SHA-256: ${formatHash(entry.sha256)}</small>
              </li>
            `).join("")}
          </ul>
        </details>
      `
      : "";

    const roleLabel = file.role === "preview"
      ? "Preview MP3"
      : file.role === "source_package"
        ? "STEMS · ZIP"
        : file.role === "full_mix"
          ? "Повний мікс"
          : "";
    const label = roleLabel || (file.container ? `${escapeHtml(file.format || "Файл")} · ${escapeHtml(file.container)}` : escapeHtml(file.format || "Файл"));
    return `
      <li>
        <span>${label}</span>
        <a href="${resolveAsset(file.path || file.file)}">${escapeHtml(file.path || file.file)}</a>
        <small>${file.description ? `${escapeHtml(file.description)} · ` : ""}SHA-256: ${formatHash(file.sha256)}</small>
        ${contents}
      </li>
    `;
  };

  const renderRegistry = (registry) => {
    const list = document.querySelector("[data-registry-list]");
    if (!list) return;

    list.innerHTML = registry.map((entry) => `
      <article class="registry-entry">
        <header>
          <p class="eyebrow">РЕЄСТР CC0 №${escapeHtml(entry.registry)}</p>
          <h2>Дата: ${escapeHtml(entry.release_date)}</h2>
          <p>Статус декларації: ${escapeHtml(entry.declaration_status || "не вказано")}</p>
        </header>
        <div class="registry-items">
          ${(entry.items || []).map((item) => registryItemMarkup(item, entry)).join("")}
        </div>
      </article>
    `).join("");
    document.querySelectorAll("[data-load-state]").forEach((node) => node.remove());
  };

  const setupPlayers = () => {
    document.querySelectorAll("[data-player]").forEach((player) => {
      if (player.dataset.ready) return;
      player.dataset.ready = "true";

      const audio = player.querySelector("[data-audio]");
      const button = player.querySelector("[data-play]");
      const seek = player.querySelector("[data-seek]");
      const time = player.querySelector("[data-time]");
      if (!audio || !button || !seek || !time) return;

      const playLabel = button.getAttribute("aria-label") || "Відтворити";
      const pauseLabel = playLabel.replace("Відтворити", "Пауза");

      button.addEventListener("click", () => {
        document.querySelectorAll("[data-audio]").forEach((otherAudio) => {
          if (otherAudio !== audio) otherAudio.pause();
        });
        if (audio.paused) {
          audio.play();
        } else {
          audio.pause();
        }
      });

      audio.addEventListener("play", () => {
        button.textContent = "Ⅱ";
        button.setAttribute("aria-label", pauseLabel);
      });

      audio.addEventListener("pause", () => {
        button.textContent = "▶";
        button.setAttribute("aria-label", playLabel);
      });

      audio.addEventListener("timeupdate", () => {
        if (audio.duration) seek.value = (audio.currentTime / audio.duration) * 100;
        time.textContent = formatTime(audio.currentTime);
      });

      audio.addEventListener("ended", () => {
        seek.value = 0;
        time.textContent = "0:00";
      });

      seek.addEventListener("input", () => {
        if (audio.duration) audio.currentTime = (Number(seek.value) / 100) * audio.duration;
      });
    });
  };

  const renderCatalog = (tracks) => {
    const lists = document.querySelectorAll("[data-track-list]");
    lists.forEach((list) => {
      const limit = Number(list.dataset.limit || tracks.length);
      list.innerHTML = tracks.slice(0, limit).map(trackRowMarkup).join("");
    });
    document.querySelectorAll("[data-load-state]").forEach((node) => node.remove());
  };

  const renderDetail = (tracks, registry = []) => {
    const detail = document.querySelector("[data-track-detail]");
    const catalog = document.querySelector("[data-catalog-view]");
    if (!detail) return;

    const id = new URLSearchParams(window.location.search).get("id");
    if (!id) return;

    const track = tracks.find((item) => [item.slug, item.id, item.cc0_item_id].filter(Boolean).includes(id));
    if (!track) {
      detail.classList.remove("hidden");
      detail.innerHTML = `<section class="content-section"><h1>Трек не знайдено.</h1><p><a href="./">Повернутися до архіву →</a></p></section>`;
      if (catalog) catalog.classList.add("hidden");
      return;
    }

    document.title = `${track.title} | CC0 Music Archive`;
    const description = document.querySelector('meta[name="description"]');
    if (description) description.setAttribute("content", track.description);

    detail.classList.remove("hidden");
    detail.innerHTML = detailMarkup(track, findRegistryItem(track, registry));
    if (catalog) catalog.classList.add("hidden");
    const copy = document.querySelector("[data-catalog-copy]");
    if (copy) copy.textContent = "Сторінка треку з прослуховуванням, описом, завантаженням, ліцензією та технічною інформацією.";
  };

  const loadTracks = async () => {
    if (!document.querySelector("[data-track-list], [data-track-detail]")) return;

    try {
      const [tracksResponse, registryResponse] = await Promise.all([
        fetch(state.tracksUrl),
        fetch(state.registryUrl),
      ]);
      if (!tracksResponse.ok) throw new Error(`HTTP ${tracksResponse.status}`);
      if (!registryResponse.ok) throw new Error(`HTTP ${registryResponse.status}`);
      const tracks = (await tracksResponse.json()).sort((a, b) => String(b.updated || b.published).localeCompare(String(a.updated || a.published)));
      const registry = await registryResponse.json();
      renderCatalog(tracks);
      renderDetail(tracks, registry);
      setupPlayers();
    } catch (error) {
      document.querySelectorAll("[data-load-state]").forEach((node) => {
        node.textContent = "Не вдалося завантажити data/tracks.json.";
      });
      console.error(error);
    }
  };

  const loadRegistry = async () => {
    if (!document.querySelector("[data-registry-list]")) return;

    try {
      const response = await fetch(state.registryUrl);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      renderRegistry(await response.json());
    } catch (error) {
      document.querySelectorAll("[data-load-state]").forEach((node) => {
        node.textContent = "Не вдалося завантажити data/cc0-registry.json.";
      });
      console.error(error);
    }
  };

  loadTracks();
  loadRegistry();
})();
