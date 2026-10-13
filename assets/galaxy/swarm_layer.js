// swarm_layer.js
// [TRIO M5a 2026-09-23] 星系戰爭層——軍官恆星＋帶兵星＋四角框
//
// Blue 設計令：
//   軍官恆星外圍 = 紅色四角框（與點擊選取 lockBox 同款）
//   帶兵星外圍   = 橘黃色四角框（同款）
//   目的：在原有光點中一眼辨識軍隊的移動
//
// 渲染紀律（沿用 galaxy.html 既有規約）：
//   - 帶兵星 InstancedMesh（1 draw call 承載全部兵）
//   - 軍官恆星 sprite 光暈（與記憶球同材料系統）
//   - 指揮鏈 LineSegments（金線語意）
//   - 四角框 DOM 疊層（與 lockBox 同款 CSS——3px 角邊+24% 角長+呼吸）
//   - 狀態色：live 呼吸 / unverifiable 穩定 / exited 暗
(async function injectSwarmLayer(){
  if (window.__swarmLayer) return; // 冪等——重載保護
  window.__swarmLayer = true;

  // 等 galaxy 主場景就緒（galaxy group 是主模組變數——用 scene children 找）
  // [H5 修] 舊版 10s 超時只是 clearInterval——promise 永遠 pending，
  // 大腦初始化 >10s 時整層靜默癱瘓（__warEnter 掛不上）。改：超時也 resolve
  //（進場函數內部自行重試），並把 window 掛載提前到本行後（見檔尾）。
  const waitScene = () => new Promise(res => {
    const t = setInterval(() => {
      if (window.__galaxyReady) { clearInterval(t); res(true); }
    }, 200);
    setTimeout(() => { clearInterval(t); res(window.__galaxyReady === true); }, 15000);
  });
  const sceneReady = await waitScene();

  // ── CSS：四角框（複製 lockBox 語系，色可變）──
  const css = document.createElement('style');
  css.textContent = `
    .sw-box{position:fixed;display:none;pointer-events:none;z-index:9;--lk:12px}
    .sw-box .lk{position:absolute;width:var(--lk);height:var(--lk)}
    .sw-box.officer{filter:drop-shadow(0 0 5px rgba(255,42,42,.95))}
    .sw-box.officer .c-tl{top:0;left:0;border-top:3px solid #ff2a2a;border-left:3px solid #ff2a2a}
    .sw-box.officer .c-tr{top:0;right:0;border-top:3px solid #ff2a2a;border-right:3px solid #ff2a2a}
    .sw-box.officer .c-bl{bottom:0;left:0;border-bottom:3px solid #ff2a2a;border-left:3px solid #ff2a2a}
    .sw-box.officer .c-br{bottom:0;right:0;border-bottom:3px solid #ff2a2a;border-right:3px solid #ff2a2a}
    .sw-box.troop{filter:drop-shadow(0 0 4px rgba(255,158,107,.85))}
    .sw-box.troop .c-tl{top:0;left:0;border-top:2px solid #ff9e6b;border-left:2px solid #ff9e6b}
    .sw-box.troop .c-tr{top:0;right:0;border-top:2px solid #ff9e6b;border-right:2px solid #ff9e6b}
    .sw-box.troop .c-bl{bottom:0;left:0;border-bottom:2px solid #ff9e6b;border-left:2px solid #ff9e6b}
    .sw-box.troop .c-br{bottom:0;right:0;border-bottom:2px solid #ff9e6b;border-right:2px solid #ff9e6b}
  `;
  document.head.appendChild(css);

  // ── 狀態 ──
  let swarm = null;      // 最新戰況
  let officers = [];     // {id,name,state,mesh(sprite),pos3}
  let troopsMesh = null; // InstancedMesh
  let chainsLines = null;// LineSegments
  let boxes = [];        // DOM 四角框池
  const MAX_BOXES = 130; // 3 軍官 + 100 兵 + 餘裕

  // ── 抓戰況（30s 輪詢——與 galaxy_data 重抓同拍）──
  const fetchSwarm = async () => {
    try {
      const _tk = new URLSearchParams(location.search).get('token') ?? '';
      const r = await fetch('/galaxy_data?swarmonly=1&cb=' + Date.now(),
        {headers: {'x-bridge-token': _tk}, cache: 'no-store'});
      const j = await r.json();
      swarm = j.swarm || null;
      rebuild();
    } catch (e) { /* fail-open——星系照轉 */ }
  };

  // ── 重建三維物件 ──
  const rebuild = () => {
    const scene = window.__swScene;
    if (!scene) return;
    // 清舊
    if (troopsMesh) { scene.remove(troopsMesh); troopsMesh.geometry.dispose(); troopsMesh.material.dispose(); }
    if (chainsLines) { scene.remove(chainsLines); chainsLines.geometry.dispose(); chainsLines.material.dispose(); }
    for (const o of officers) if (o.mesh) scene.remove(o.mesh);
    officers = []; boxes.forEach(b => b.remove()); boxes = [];
    if (!swarm || !swarm.campaign || swarm.campaign.phase === 'aborted') return;
    if (swarm.campaign.phase === 'done') return; // 完戰收兵——不留殘星

    // 軍官恆星：sprite 光暈（紅核白暈——比記憶球亮一階）
    const offTex = makeGlowTex('#ff5555', '#fff0f0');
    for (const o of (swarm.officers || [])) {
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({
        map: offTex, transparent: true, depthWrite: false,
        blending: THREE.AdditiveBlending,
      }));
      sp.scale.set(90, 90, 1);
      sp.position.set(o.pos[0], o.pos[1], o.pos[2]);
      scene.add(sp);
      officers.push({...o, mesh: sp, pos3: new THREE.Vector3(...o.pos)});
    }

    // 帶兵星：InstancedMesh 球（橘黃）
    const tList = swarm.troops || [];
    if (tList.length) {
      const geo = new THREE.SphereGeometry(9, 8, 8);
      const mat = new THREE.MeshBasicMaterial({color: 0xff9e6b, transparent: true, opacity: 0.95});
      troopsMesh = new THREE.InstancedMesh(geo, mat, tList.length);
      const m = new THREE.Matrix4();
      tList.forEach((t, i) => {
        m.setPosition(t.pos[0], t.pos[1], t.pos[2]);
        troopsMesh.setMatrixAt(i, m);
      });
      troopsMesh.instanceMatrix.needsUpdate = true;
      scene.add(troopsMesh);
    }

    // 指揮鏈：軍官→兵 金線（弱透明——不搶記憶金線）
    const chains = swarm.chains || [];
    if (chains.length && officers.length && tList.length) {
      const pts = new Float32Array(chains.length * 6);
      chains.forEach(([oi, ti], i) => {
        const o = officers[oi], t = tList[ti];
        pts.set([o.pos[0], o.pos[1], o.pos[2], t.pos[0], t.pos[1], t.pos[2]], i * 6);
      });
      const g = new THREE.BufferGeometry();
      g.setAttribute('position', new THREE.BufferAttribute(pts, 3));
      chainsLines = new THREE.LineSegments(g,
        new THREE.LineBasicMaterial({color: 0xff9e6b, transparent: true, opacity: 0.28}));
      scene.add(chainsLines);
    }

    // DOM 四角框池
    for (let i = 0; i < Math.min(MAX_BOXES, officers.length + tList.length); i++) {
      const isOfficer = i < officers.length;
      const d = document.createElement('div');
      d.className = 'sw-box ' + (isOfficer ? 'officer' : 'troop');
      d.innerHTML = '<div class="lk c-tl"></div><div class="lk c-tr"></div><div class="lk c-bl"></div><div class="lk c-br"></div>';
      document.body.appendChild(d);
      boxes.push(d);
    }
  };

  // 光暈貼圖（與記憶球同做法）
  const makeGlowTex = (core, halo) => {
    const c = document.createElement('canvas'); c.width = c.height = 128;
    const x = c.getContext('2d');
    const g = x.createRadialGradient(64, 64, 4, 64, 64, 64);
    g.addColorStop(0, core); g.addColorStop(0.25, halo);
    g.addColorStop(1, 'rgba(0,0,0,0)');
    x.fillStyle = g; x.fillRect(0, 0, 128, 128);
    const tex = new THREE.CanvasTexture(c);
    return tex;
  };

  // ── 每幀：四角框追蹤 + live 呼吸 ──
  window.__swarmTick = (camera) => {
    if (!swarm || !boxes.length) return;
    const tList = swarm.troops || [];
    const pulse = 1 + 0.06 * Math.sin(performance.now() / 300); // lockBox 同款呼吸
    const v = new THREE.Vector3();
    let bi = 0;
    // 軍官框（大）
    for (const o of officers) {
      if (bi >= boxes.length) break;
      v.copy(o.pos3).project(camera);
      if (v.z > 1) { boxes[bi].style.display = 'none'; bi++; continue; }
      const x = (v.x * 0.5 + 0.5) * innerWidth, y = (-v.y * 0.5 + 0.5) * innerHeight;
      const size = 56;
      const b = boxes[bi++];
      b.style.display = o.state === 'live' ? 'block' : (o.state === 'unverifiable' ? 'block' : 'none');
      b.style.width = b.style.height = size + 'px';
      b.style.left = (x - size / 2) + 'px'; b.style.top = (y - size / 2) + 'px';
      b.style.transform = 'scale(' + (o.state === 'live' ? pulse : 1) + ')';
      b.style.setProperty('--lk', Math.max(14, size * 0.24) + 'px');
      b.style.opacity = o.state === 'unverifiable' ? '0.6' : '1';
    }
    // 兵框（小）
    for (const t of tList) {
      if (bi >= boxes.length) break;
      v.set(t.pos[0], t.pos[1], t.pos[2]).project(camera);
      if (v.z > 1) { boxes[bi].style.display = 'none'; bi++; continue; }
      const x = (v.x * 0.5 + 0.5) * innerWidth, y = (-v.y * 0.5 + 0.5) * innerHeight;
      const size = 26;
      const b = boxes[bi++];
      b.style.display = t.state === 'live' ? 'block' : 'none'; // exited 兵不併框
      b.style.width = b.style.height = size + 'px';
      b.style.left = (x - size / 2) + 'px'; b.style.top = (y - size / 2) + 'px';
      b.style.transform = 'scale(' + (t.state === 'live' ? pulse : 1) + ')';
      b.style.setProperty('--lk', Math.max(8, size * 0.24) + 'px');
    }
    for (; bi < boxes.length; bi++) boxes[bi].style.display = 'none';
  };

  fetchSwarm();
  setInterval(fetchSwarm, 30000);

  // ═══ [M5b 2026-09-23] 作戰模式——VIZ 第六模式＋回放複盤台 ═══
  // Blue 令：長住層弱化、作戰資訊強化；回放+側邊事件清單可點跳轉
  const WAR = {
    on: false, playing: false, cursor: 0, live: false,
    events: [], t0: 0, t1: 1, campaignId: null,
    savedOpacity: null, replayTroops: null, replayBoxes: [],
    eventPanel: null, timeBar: null,
  };

  // ── 進入作戰模式（掛 window.__warEnter——galaxy.html setVizMode 呼叫）──
  let liveWatchTimer = null;
  const enterWarMode = async () => {
    if (WAR.on) return;
    WAR.on = true;
    // 弱化長住層——透過主體掛的 window 參照（__swDim/__swRestore 由 galaxy.html 提供）
    try { if (window.__swDim) window.__swDim(WAR.saved = {}); } catch (e) {}
    buildWarUI();
    buildMissionsPanel(); // [H5 2026-10-08] 左側任務面板——同時看見「要做什麼」與「腦內正在發生什麼」
    await loadCampaignList();
    // [Blue 問出的縫隙] 使用者可能先進作戰模式等著、再回對話開戰——
    // 每 5s 輕查活躍戰役，開打自動切 LIVE（在 live/回放中不吵）
    liveWatchTimer = setInterval(async () => {
      if (!WAR.on || WAR.live) return;
      try {
        const _tk = new URLSearchParams(location.search).get('token') ?? '';
        const lr = await fetch('/galaxy_data?swarmonly=1&cb=' + Date.now(),
          {headers: {'x-bridge-token': _tk}, cache: 'no-store'});
        const lj = await lr.json();
        if (lj.swarm && lj.swarm.campaign &&
            ['planning', 'committed', 'running'].includes(lj.swarm.campaign.phase)) {
          await loadCampaignList(); // 重建下拉（含 LIVE 項）→ 自動 enterLive
        }
      } catch (e) {}
    }, 5000);
  };

  // ── 退出作戰模式（掛 window.__warExit——還原走主體 __swRestore）──
  const exitWarMode = () => {
    WAR.on = false; WAR.playing = false; WAR.live = false;
    if (liveWatchTimer) { clearInterval(liveWatchTimer); liveWatchTimer = null; }
    if (liveSse) { try { liveSse.close(); } catch(e){} liveSse = null; }
    try { if (window.__swRestore) window.__swRestore(WAR.saved); } catch (e) {}
    if (WAR.replayTroops) { scene2().remove(WAR.replayTroops); WAR.replayTroops = null; }
    WAR.replayBoxes.forEach(b => b.remove()); WAR.replayBoxes = [];
    if (WAR.eventPanel) { WAR.eventPanel.remove(); WAR.eventPanel = null; }
    if (WAR.timeBar) { WAR.timeBar.remove(); WAR.timeBar = null; }
    if (WAR.missionsPanel) { WAR.missionsPanel.remove(); WAR.missionsPanel = null; } // [H5]
  };

  // [H5 修] 提前掛 window 進出點——後面初始化流程再慢/再炸，
  // 模式切換（setVizMode → __warEnter）都不會找不到函數。
  window.__warEnter = enterWarMode;
  window.__warExit = exitWarMode;

  const scene2 = () => window.__swScene;

  // ── UI：戰役選單＋回放時間軸＋事件清單 ──
  const buildWarUI = () => {
    // 底部回放時間軸
    const bar = document.createElement('div');
    bar.style.cssText = 'position:fixed;bottom:20px;left:50%;transform:translateX(-50%);z-index:60;display:flex;gap:8px;align-items:center;background:rgba(8,14,10,.88);border:1px solid #ff9e6b55;border-radius:14px;padding:8px 14px;user-select:none;backdrop-filter:blur(6px)';
    bar.innerHTML = `
      <select id="warCampaignSel" style="background:#0c1410;color:#ffb98a;border:1px solid #ff9e6b44;border-radius:8px;padding:4px 8px;font-size:12px;max-width:220px"></select>
      <button id="warPlay" style="background:#ff9e6b22;color:#ffb98a;border:1px solid #ff9e6b66;border-radius:8px;padding:4px 12px;cursor:pointer;font-size:13px">▶</button>
      <input id="warSeek" type="range" min="0" max="1000" value="0" style="width:280px;accent-color:#ff9e6b">
      <span id="warTime" style="color:#ffb98a;font-size:12px;min-width:90px">--:--</span>
      <button id="warExit" style="background:transparent;color:#8fb8a5;border:1px solid #2a3d33;border-radius:8px;padding:4px 10px;cursor:pointer;font-size:12px">退出作戰</button>`;
    document.body.appendChild(bar);
    WAR.timeBar = bar;
    bar.querySelector('#warExit').onclick = () => {
      // 經主體 setVizMode('galaxy') 走正規還原（含本層 __warExit）
      const btns = document.querySelectorAll('button[data-viz="galaxy"]');
      if (btns.length) btns[0].click();
      else exitWarMode();
    };
    bar.querySelector('#warPlay').onclick = () => { WAR.playing = !WAR.playing; bar.querySelector('#warPlay').textContent = WAR.playing ? '⏸' : '▶'; };
    bar.querySelector('#warSeek').oninput = (e) => { WAR.cursor = +e.target.value; WAR.playing = false; bar.querySelector('#warPlay').textContent='▶'; applyReplay(); };
    // 側邊事件清單
    const panel = document.createElement('div');
    panel.style.cssText = 'position:fixed;right:16px;top:110px;bottom:90px;width:260px;z-index:55;background:rgba(8,14,10,.88);border:1px solid #ff9e6b33;border-radius:12px;padding:10px;overflow-y:auto;font:12px system-ui;color:#cfe0d5;backdrop-filter:blur(6px)';
    panel.innerHTML = '<div style="color:#ffb98a;font-weight:600;margin-bottom:6px">📜 作戰事件流（點擊跳轉）</div><div id="warEventList">載入中…</div>';
    document.body.appendChild(panel);
    WAR.eventPanel = panel;
  };

  // ── [H5 2026-10-08] 左側任務面板——戰爭模式獨家場景 ──
  // Phase H spec §4：「使用者開戰爭模式 → 同時看 任務面板＋大腦圖譜戰爭模式
  //   = 一眼同時看見『要做什麼』與『腦內正在發生什麼』」
  // 資料：/galaxy_missions（H4 排程卡＋專案門）。溫度語彙與 H4 kanban 一致：
  // 生活卡紫暖色＋心意一行；工作卡冷靜緊湊。
  const fmtNext = (iso) => {
    if (!iso) return '';
    const ms = new Date(iso) - Date.now();
    if (ms < 0) return '';
    const mins = Math.round(ms / 60000);
    if (mins < 60) return mins + ' 分鐘後';
    if (mins < 1440) return Math.round(mins / 60) + ' 小時後';
    return Math.round(mins / 1440) + ' 天後';
  };
  const buildMissionsPanel = async () => {
    const panel = document.createElement('div');
    panel.style.cssText = 'position:fixed;left:16px;top:110px;bottom:90px;width:270px;z-index:55;background:rgba(10,8,16,.9);border:1px solid #b18cff33;border-radius:12px;padding:10px;overflow-y:auto;font:12px system-ui;color:#d5cfe5;backdrop-filter:blur(6px)';
    panel.innerHTML = '<div style=\"color:#c9b3ff;font-weight:600;margin-bottom:6px\">🗺️ 任務面板（載入中…）</div>';
    document.body.appendChild(panel);
    WAR.missionsPanel = panel;
    try {
      const _tk = new URLSearchParams(location.search).get('token') ?? '';
      const r = await fetch('/galaxy_missions?cb=' + Date.now(),
        {headers: {'x-bridge-token': _tk}, cache: 'no-store'});
      const j = await r.json();
      if (j.error) throw new Error(j.error);
      const life = (j.schedules || []).filter(x => x.warmth === 'life');
      const work = (j.schedules || []).filter(x => x.warmth !== 'life');
      const projs = (j.projects || []).filter(p => p.status === 'active' || p.status === 'waiting');
      let html = '<div style="color:#c9b3ff;font-weight:600;margin-bottom:6px">🗺️ 任務面板 <span style="color:#8a7fa8;font-weight:400">· ' + (j.schedules||[]).length + ' 個約定</span></div>';
      if (projs.length) {
        html += '<div style="color:#8fb8a5;font-weight:600;margin:4px 0">專案</div>';
        for (const p of projs.slice(0, 6)) {
          html += '<div style="padding:3px 0;color:#cfe0d5">▸ ' + p.title +
            ' <span style="color:' + (p.status==='active'?'#7dd8a0':'#e0c060') + ';font-size:11px">' +
            (p.status==='active'?'進行中':'等待中') + '</span></div>';
        }
      }
      if (life.length) {
        html += '<div style="color:#c9b3ff;font-weight:600;margin:8px 0 4px">生活 · 心意</div>';
        for (const c of life) {
          const nx = fmtNext(c.nextRun);
          html += '<div style="background:linear-gradient(135deg,#b18cff14,#7ee8d40d);border:1px solid #b18cff2e;border-radius:9px;padding:7px 9px;margin-bottom:6px">' +
            '<div style="font-weight:600;color:#e8e2f5">' + c.name + '</div>' +
            (c.warmLine ? '<div style="color:#a89cc2;margin:3px 0">' + c.warmLine + '</div>' : '') +
            '<div style="color:#c9b3ff;font-size:11px">♡ ' + (nx || c.human) + '</div></div>';
        }
      }
      if (work.length) {
        html += '<div style="color:#8a7fa8;font-weight:600;margin:8px 0 4px">工作 · 維運</div>';
        for (const c of work.slice(0, 10)) {
          html += '<div style="padding:2px 0;color:#a89fba;font-size:11px">· ' + c.name +
            ' <span style="color:#6d6584">' + c.human + '</span></div>';
        }
        if (work.length > 10) html += '<div style="color:#6d6584;font-size:11px">…還有 ' + (work.length-10) + ' 個</div>';
      }
      panel.innerHTML = html;
    } catch (e) {
      panel.innerHTML = '<div style="color:#c9b3ff;font-weight:600">🗺️ 任務面板</div><div style="color:#8a7fa8">載入失敗：' + e.message + '</div>';
    }
  };

  // ── 戰役列表（LIVE 優先：有活躍戰役自動進即時戰況）──
  const loadCampaignList = async () => {
    try {
      const _tk = new URLSearchParams(location.search).get('token') ?? '';
      // 查活躍戰役（swarmonly 輕量端點）
      let activeId = null, activePhase = null;
      try {
        const lr = await fetch('/galaxy_data?swarmonly=1&cb=' + Date.now(),
          {headers: {'x-bridge-token': _tk}, cache: 'no-store'});
        const lj = await lr.json();
        if (lj.swarm && lj.swarm.campaign &&
            ['planning', 'committed', 'running'].includes(lj.swarm.campaign.phase)) {
          activeId = lj.swarm.campaign.id;
          activePhase = lj.swarm.campaign.phase;
        }
      } catch (e) {}
      const r = await fetch('/galaxy_swarm_campaigns', {headers: {'x-bridge-token': _tk}});
      const j = await r.json();
      const sel = document.querySelector('#warCampaignSel');
      if (!sel) return;
      sel.innerHTML = '';
      if (activeId) {
        const live = document.createElement('option');
        live.value = '__live__';
        live.textContent = `🔴 LIVE 進行中（${activePhase}）`;
        sel.appendChild(live);
      }
      for (const c of (j.campaigns || [])) {
        const opt = document.createElement('option');
        opt.value = c.campaignId;
        opt.textContent = `${c.campaignId.slice(-8)} · ${c.spawns}兵 ${c.success}✓${c.fail}✗`;
        sel.appendChild(opt);
      }
      sel.onchange = () => sel.value === '__live__' ? enterLive() : loadEvents(sel.value);
      if (activeId) { sel.value = '__live__'; await enterLive(); }
      else if ((j.campaigns || []).length) await loadEvents(j.campaigns[0].campaignId);
      else document.querySelector('#warEventList').innerHTML = '<span style="color:#6a8a7a">尚無作戰紀錄</span>';
    } catch (e) { console.warn('[war] 列表失敗', e); }
  };

  // ── LIVE 即時戰況：事件驅動推送（SSE）＋30s 輪詢 fallback ──
  let liveSse = null;
  const liveFeed = document.createElement('div');
  const enterLive = async () => {
    WAR.live = true; WAR.playing = false;
    // 清回放殘留
    if (WAR.replayTroops) { scene2().remove(WAR.replayTroops); WAR.replayTroops = null; }
    if (WAR.timeBar) {
      const sk = WAR.timeBar.querySelector('#warSeek'); if (sk) sk.disabled = true;
      const pb = WAR.timeBar.querySelector('#warPlay'); if (pb) pb.disabled = true;
      const tt = WAR.timeBar.querySelector('#warTime'); if (tt) tt.textContent = '🔴 LIVE';
    }
    // 事件驅動：SSE 訂閱（每個作戰事件即時到達——零輪詢）
    if (!liveSse) {
      liveSse = new EventSource('/galaxy_swarm_live');
      liveSse.onmessage = (msg) => {
        try {
          const e = JSON.parse(msg.data);
          onLiveEvent(e);
        } catch (err) {}
      };
      liveSse.onerror = () => { /* EventSource 自動重連 */ };
    }
    // LIVE 事件牆（即時滾動——側欄變實況室）
    const list = document.querySelector('#warEventList');
    if (list) {
      list.innerHTML = '';
      liveFeed.style.cssText = '';
      list.appendChild(liveFeed);
      liveFeed.innerHTML = '<div style="color:#6a8a7a">等待作戰事件…（事件驅動——零延遲）</div>';
    }
    // 即時層立即刷一幀（SSE 只推「未來」事件——現況先拉一次）
    fetchSwarm();
  };

  // 單一 LIVE 事件到達：滾動牆＋觸發即時層刷新（輕節流）
  let lastRefresh = 0;
  const onLiveEvent = (e) => {
    if (!WAR.live) return;
    // 事件牆（最新在上，上限 60 行）
    const icon = {spawn:'🚀',success:'✅',fail:'❌',intel_share:'📡',intel_refute:'🗑️',cost_tick:'💰',commit:'⚔️',end:'🏁',campaign_open:'📋',gate_pass:'🚧',dispatch:'📤',harvest:'🌳'}[e.type] || '·';
    const t = e.t ? new Date(e.t) : new Date();
    const row = document.createElement('div');
    row.style.cssText = 'padding:2px 4px;border-bottom:1px solid #ffffff08';
    row.innerHTML = '<span style="color:#6a8a7a">' +
      String(t.getHours()).padStart(2,'0')+':'+String(t.getMinutes()).padStart(2,'0')+':'+String(t.getSeconds()).padStart(2,'0') +
      '</span> ' + icon + ' <span style="color:' + (e.type==='fail'?'#ff6a6a':e.type==='success'?'#7fd894':'#cfe0d5') + '">' +
      e.type + (e.agentId ? ' · '+e.agentId : '') + '</span>';
    if (liveFeed.firstChild) liveFeed.insertBefore(row, liveFeed.firstChild);
    else liveFeed.appendChild(row);
    while (liveFeed.children.length > 60) liveFeed.removeChild(liveFeed.lastChild);
    // 即時層刷新節流（1s 內多事件合一刷）
    const now = performance.now();
    if (now - lastRefresh > 1000) {
      lastRefresh = now;
      fetchSwarm();
    }
    // end 事件 → 戰役結束：LIVE 自動收攤，提示可回放
    if (e.type === 'end') {
      const tip = document.createElement('div');
      tip.style.cssText = 'color:#ffb98a;font-weight:600;padding:6px;margin-top:6px;border-top:1px solid #ff9e6b44';
      tip.textContent = '🏁 戰役結束——從下拉選單選本戰役即可回放';
      liveFeed.appendChild(tip);
    }
  };

  // ── 載入事件流＋建回放場景 ──
  const loadEvents = async (id) => {
    WAR.live = false; // 回放模式
    try {
      const _tk = new URLSearchParams(location.search).get('token') ?? '';
      const r = await fetch('/galaxy_swarm_events?id=' + encodeURIComponent(id), {headers: {'x-bridge-token': _tk}});
      const j = await r.json();
      WAR.events = j.events || [];
      WAR.campaignId = id;
      if (WAR.events.length > 1) {
        WAR.t0 = new Date(WAR.events[0].t).getTime();
        WAR.t1 = new Date(WAR.events[WAR.events.length - 1].t).getTime();
      }
      buildReplayScene();
      buildEventList();
      WAR.cursor = 0; WAR.playing = true;
      const pb = document.querySelector('#warPlay'); if (pb) pb.textContent = '⏸';
    } catch (e) { console.warn('[war] 事件流失敗', e); }
  };

  // 回放場景：兵星＋四角框（沿用 M5a 語系）
  const buildReplayScene = () => {
    const sc = scene2();
    if (!sc) return;
    if (WAR.replayTroops) { sc.remove(WAR.replayTroops); }
    WAR.replayBoxes.forEach(b => b.remove()); WAR.replayBoxes = [];
    // 兵=事件中的 agentId 集合
    const agents = [...new Set(WAR.events.filter(e => e.agentId).map(e => e.agentId))];
    const geo = new THREE.SphereGeometry(9, 8, 8);
    const mtl = new THREE.MeshBasicMaterial({color: 0xff9e6b, transparent: true, opacity: 0.95});
    WAR.replayTroops = new THREE.InstancedMesh(geo, mtl, Math.max(1, agents.length));
    WAR.replayTroops.visible = false; // 播到才亮
    sc.add(WAR.replayTroops);
    WAR.agentIndex = {}; agents.forEach((a, i) => WAR.agentIndex[a] = i);
    // 兵位置：golden angle 環繞
    const m4 = new THREE.Matrix4();
    agents.forEach((a, i) => {
      const ang = i * 2.399963;
      const r = 600 + (i % 5) * 150;
      m4.setPosition(r * Math.cos(ang), 200 + (i % 7) * 80, r * Math.sin(ang));
      WAR.replayTroops.setMatrixAt(i, m4);
    });
    WAR.replayTroops.instanceMatrix.needsUpdate = true;
    WAR.agentPos = agents.map((a, i) => {
      const ang = i * 2.399963; const r = 600 + (i % 5) * 150;
      return [r * Math.cos(ang), 200 + (i % 7) * 80, r * Math.sin(ang)];
    });
  };

  // 事件清單（可點跳轉）
  const buildEventList = () => {
    const list = document.querySelector('#warEventList');
    if (!list) return;
    list.innerHTML = '';
    WAR.events.slice(0, 200).forEach((e, i) => {
      const d = document.createElement('div');
      d.style.cssText = 'padding:3px 4px;border-radius:6px;cursor:pointer;margin-bottom:2px';
      const icon = {spawn:'🚀',success:'✅',fail:'❌',intel_share:'📡',intel_refute:'🗑️',cost_tick:'💰',commit:'⚔️',end:'🏁',campaign_open:'📋',gate_pass:'🚧',dispatch:'📤',harvest:'🌳'}[e.type] || '·';
      const t = new Date(e.t);
      d.innerHTML = `<span style="color:#6a8a7a">${String(t.getHours()).padStart(2,'0')}:${String(t.getMinutes()).padStart(2,'0')}:${String(t.getSeconds()).padStart(2,'0')}</span> ${icon} ${e.type}${e.agentId ? ' · ' + e.agentId : ''}`;
      d.onmouseenter = () => d.style.background = '#ff9e6b18';
      d.onmouseleave = () => d.style.background = 'transparent';
      d.onclick = () => {
        WAR.cursor = Math.round(((t.getTime() - WAR.t0) / Math.max(1, WAR.t1 - WAR.t0)) * 1000);
        WAR.playing = false;
        const pb = document.querySelector('#warPlay'); if (pb) pb.textContent = '▶';
        const sk = document.querySelector('#warSeek'); if (sk) sk.value = WAR.cursor;
        applyReplay();
        d.style.background = '#ff9e6b33';
        setTimeout(() => d.style.background = 'transparent', 600);
      };
      list.appendChild(d);
    });
  };

  // ── 每幀回放：cursor → 事件套用 ──
  const applyReplay = () => {
    if (!WAR.on || WAR.live || !WAR.events.length) return;
    const u = WAR.cursor / 1000;
    const nowT = WAR.t0 + u * (WAR.t1 - WAR.t0);
    const tl = document.querySelector('#warTime');
    if (tl) {
      const d = new Date(nowT);
      tl.textContent = `${String(d.getHours()).padStart(2,'0')}:${String(d.getMinutes()).padStart(2,'0')}:${String(d.getSeconds()).padStart(2,'0')}`;
    }
    if (!WAR.replayTroops || !WAR.agentIndex) return;
    // 依事件時序決定每兵狀態
    const agentState = {}; // id -> 0 未生 1 live 2 ok 3 fail
    for (const e of WAR.events) {
      const et = new Date(e.t).getTime();
      if (et > nowT) break;
      if (!e.agentId) continue;
      if (e.type === 'spawn') agentState[e.agentId] = 1;
      else if (e.type === 'success') agentState[e.agentId] = 2;
      else if (e.type === 'fail') agentState[e.agentId] = 3;
    }
    WAR.replayTroops.visible = true;
    const col = new THREE.Color();
    let any = false;
    for (const [aid, st] of Object.entries(agentState)) {
      const idx = WAR.agentIndex[aid];
      if (idx === undefined) continue;
      any = true;
      col.set(st === 2 ? 0x7fd894 : st === 3 ? 0xff4a4a : 0xff9e6b);
      WAR.replayTroops.setColorAt(idx, col);
    }
    if (WAR.replayTroops.instanceColor) WAR.replayTroops.instanceColor.needsUpdate = true;
    WAR.replayTroops.count = Math.max(1, Object.keys(agentState).length ? WAR.replayTroops.instanceMatrix.count : 0);
  };

  // 回放推進（掛進 swarmTick）
  const warTick = () => {
    if (!WAR.on) return;
    if (WAR.playing) {
      WAR.cursor += 2.2; // 播放速度
      if (WAR.cursor >= 1000) { WAR.cursor = 1000; WAR.playing = false; const pb=document.querySelector('#warPlay'); if(pb) pb.textContent='▶'; }
      const sk = document.querySelector('#warSeek'); if (sk) sk.value = WAR.cursor;
    }
    applyReplay();
  };
  window.__warTick = warTick;

  // 掛進主 tick
  const _origSwarmTick = window.__swarmTick;
  window.__swarmTick = (camera) => {
    // 作戰模式：live（即時戰況）即時層照跑；回放模式才暫停
    if (_origSwarmTick && (!WAR.on || WAR.live)) _origSwarmTick(camera);
    warTick();
  };

  // [M5b fix] galaxy.html 已原生支援 swarm 模式（VIZ_NAMES+setVizMode 分支）——
  // 掛 window 進出點，不需攔截
})();
