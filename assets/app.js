(() => {
  'use strict';

  const REPO_OWNER = 'LianXia233';
  const REPO_NAME = 'H5000M-CI-Qmodem';
  const WALLPAPERS = window.WALLPAPERS || [
    'https://files.seeusercontent.com/2026/10/31/aE1a/145952531_p1.jpg',
    'https://files.seeusercontent.com/2026/06/29/uu4H/bg1.jpg'
  ];

  let currentMirror = 'acg2';
  let currentDeviceFilter = 'all';
  let currentVariantFilter = 'all';
  let searchQuery = '';
  let allReleases = [];
  let cloudState = 'loading';
  let cloudErrorMsg = '';

  const KNOWN_CONFIGS = [
    'AP3000M-qmodem-next', 'AP3000M-modem-pro', 'AP3000M-qmodem',
    'H5000M-qmodem-next', 'H5000M-modem-pro', 'H5000M-qmodem',
    'X86-qmodem-next', 'X86-qmodem'
  ].sort((a, b) => b.length - a.length);

  function parseAssetName(name) {
    for (const cfg of KNOWN_CONFIGS) {
      if (!name.startsWith(cfg + '-')) continue;
      const rest = name.slice(cfg.length + 1);
      const m = rest.match(/^(\d{8})-(.+)$/);
      if (!m) continue;
      const d = m[1];
      return {
        config: cfg,
        device: cfg.split('-')[0],
        variant: cfg.includes('modem-pro') ? 'modem-pro' : (cfg.includes('qmodem-next') ? 'next' : 'classic'),
        date: `${d.slice(0, 4)}-${d.slice(4, 6)}-${d.slice(6, 8)}`
      };
    }
    return null;
  }

  function inferDevice(tag) {
    if (tag.startsWith('AP3000M')) return 'AP3000M';
    if (tag.startsWith('X86') || tag.startsWith('x86')) return 'X86';
    return 'H5000M';
  }

  function inferVariant(tag) {
    if (tag.includes('modem-pro')) return 'modem-pro';
    if (tag.includes('qmodem-next')) return 'next';
    return 'classic';
  }

  function formatBytes(bytes, decimals = 1) {
    if (!bytes || bytes === 0) return '0 B';
    const k = 1024;
    const dm = decimals < 0 ? 0 : decimals;
    const sizes = ['B', 'KB', 'MB', 'GB'];
    const i = Math.floor(Math.log(bytes) / Math.log(k));
    return `${parseFloat((bytes / Math.pow(k, i)).toFixed(dm))} ${sizes[i]}`;
  }

  function transformUrl(originalUrl) {
    if (!originalUrl) return '#';
    if (currentMirror === 'acg2') return `https://gh.acg2.mom/${originalUrl}`;
    if (currentMirror === 'ghproxy') return `https://ghproxy.net/${originalUrl}`;
    return originalUrl;
  }

  function escapeHtml(str) {
    return String(str || '').replace(/[&<>"']/g, s => ({
      '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
    }[s]));
  }

  function renderReleases() {
    const container = document.getElementById('releasesContainer');
    if (!container) return;

    if (cloudState === 'loading') {
      container.innerHTML = `
        <div class="glass-card" style="grid-column:1/-1; padding:40px; text-align:center;">
          <p style="font-weight:800; font-size:1.08rem; color:var(--text-main);">正在从 GitHub 获取最新固件…</p>
          <p style="font-size:0.88rem; color:var(--text-muted); margin-top:4px;">首次加载约需 1 秒，请稍候</p>
        </div>
      `;
      return;
    }

    if (cloudState === 'error') {
      container.innerHTML = `
        <div class="glass-card" style="grid-column:1/-1; padding:40px; text-align:center;">
          <p style="font-weight:800; font-size:1.08rem; color:var(--text-main);">云端 Release 获取失败</p>
          <p style="font-size:0.88rem; color:var(--text-muted); margin-top:4px;">${escapeHtml(cloudErrorMsg)} · 可直接前往 GitHub Releases 页下载</p>
          <div style="margin-top:16px; display:flex; gap:10px; justify-content:center; flex-wrap:wrap;">
            <button class="btn btn-primary btn-sm" onclick="window.appFetchReleases()" type="button">重新获取</button>
            <a href="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases" target="_blank" rel="noopener noreferrer" class="btn btn-secondary btn-sm">打开 GitHub Releases</a>
          </div>
        </div>
      `;
      return;
    }

    const filtered = allReleases.filter(rel => {
      if (currentDeviceFilter !== 'all' && rel.device !== currentDeviceFilter) return false;
      if (currentVariantFilter !== 'all' && rel.variant !== currentVariantFilter) return false;
      if (searchQuery) {
        const hay = [
          rel.name, rel.tag_name, rel.config || '', rel.build_date || '',
          rel.device, rel.variant,
          rel.primary_asset ? rel.primary_asset.name : '',
          ...(rel.extra_assets || []).map(a => a.name)
        ].join(' ').toLowerCase();
        if (!hay.includes(searchQuery)) return false;
      }
      return true;
    });

    if (filtered.length === 0) {
      container.innerHTML = `
        <div class="glass-card" style="grid-column:1/-1; padding:40px; text-align:center;">
          <p style="font-weight:800; font-size:1.08rem; color:var(--text-main);">未找到匹配的固件</p>
          <p style="font-size:0.88rem; color:var(--text-muted); margin-top:4px;">请调整筛选条件或清空搜索关键词</p>
        </div>
      `;
      return;
    }

    container.innerHTML = filtered.map((rel, idx) => {
      const badgeClass = rel.variant === 'modem-pro' ? 'fw-badge-base' : (rel.variant === 'next' ? 'fw-badge-netwiz' : 'fw-badge-mt');
      const variantLabel = rel.variant === 'modem-pro' ? 'Modem Pro 统一版' : (rel.variant === 'next' ? 'QModem Next' : '经典 LuCI');
      const primary = rel.primary_asset;
      const dlUrl = primary ? transformUrl(primary.download_url) : `https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/tag/${encodeURIComponent(rel.tag_name)}`;
      const extras = rel.extra_assets || [];

      return `
        <article class="fw-card glass-card glass-card-interactive">
          <div class="fw-header">
            <div class="fw-device-title">
              <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="var(--primary)" stroke-width="2.2"><rect width="20" height="8" x="2" y="14" rx="2"/><path d="M6 18h.01M10 18h.01M15 10v4"/></svg>
              <span>${escapeHtml(rel.device)} · ${escapeHtml(rel.tag_name)}</span>
            </div>
            <span class="fw-badge ${badgeClass}">${variantLabel}</span>
          </div>

          ${primary ? `
            <div class="fw-filename-box">
              <span class="fw-filename-text" title="${escapeHtml(primary.name)}">${escapeHtml(primary.name)}</span>
              <button class="copy-btn" onclick="window.appCopy('${escapeHtml(primary.name)}', '文件名')" type="button" title="复制文件名">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><rect width="14" height="14" x="8" y="8" rx="2"/><path d="M4 16c-1.1 0-2-.9-2-2V4c0-1.1.9-2 2-2h10c1.1 0 2 .9 2 2"/></svg>
              </button>
            </div>
          ` : ''}

          <p class="fw-desc-text">${escapeHtml(rel.description)}</p>

          <div class="fw-meta-row">
            ${primary ? `<span>大小：<strong style="color:var(--text-main)">${formatBytes(primary.size)}</strong></span>` : ''}
            ${rel.build_date ? `<span>编译：<strong style="color:var(--text-main)">${escapeHtml(rel.build_date)}</strong></span>` : ''}
            ${rel.config ? `<span>配置：<strong style="color:var(--text-main)">${escapeHtml(rel.config)}</strong></span>` : ''}
          </div>

          <div class="fw-actions">
            <a href="${escapeHtml(dlUrl)}" class="btn btn-primary btn-sm" target="_blank" rel="noopener noreferrer" ${primary ? 'download' : ''}>
              <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.3"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" x2="12" y1="15" y2="3"/></svg>
              ${primary ? '下载主固件' : '查看 Release'}
            </a>
            ${primary ? `
              <button class="btn btn-secondary btn-icon" onclick="window.appCopy('${escapeHtml(dlUrl)}', '下载直链')" type="button" title="复制加速直链">
                <svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M10 13a5 5 0 0 0 7.54.54l3-3a5 5 0 0 0-7.07-7.07l-1.72 1.71"/><path d="M14 11a5 5 0 0 0-7.54-.54l-3 3a5 5 0 0 0 7.07 7.07l1.71-1.71"/></svg>
              </button>
            ` : ''}
            ${extras.length > 0 ? `
              <button class="btn btn-secondary btn-sm" onclick="window.appToggleExtra(${idx})" type="button">
                其余格式 (${extras.length})
              </button>
            ` : ''}
          </div>

          ${extras.length > 0 ? `
            <div class="extra-assets-list" id="extraAssets-${idx}">
              ${extras.map(ex => `
                <div class="extra-asset-row">
                  <div style="min-width:0;">
                    <div style="font-weight:700; color:var(--text-main);">${escapeHtml(ex.format)} · ${escapeHtml(ex.title)}</div>
                    <div style="font-family:var(--font-mono); color:var(--text-muted); overflow:hidden; text-overflow:ellipsis; white-space:nowrap;">${escapeHtml(ex.name)} (${formatBytes(ex.size)})</div>
                  </div>
                  <a href="${escapeHtml(transformUrl(ex.download_url))}" class="btn btn-secondary btn-sm" target="_blank" rel="noopener noreferrer" download>下载</a>
                </div>
              `).join('')}
            </div>
          ` : ''}
        </article>
      `;
    }).join('');
  }

  async function fetchLiveReleases() {
    const btnText = document.getElementById('refreshBtnText');
    const statusEl = document.getElementById('releaseStatusText');
    if (btnText) btnText.textContent = '正在获取...';
    cloudState = 'loading';
    renderReleases();

    try {
      const response = await fetch(`https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}/releases?per_page=100`);
      if (!response.ok) throw new Error(`GitHub API 返回 HTTP ${response.status}`);
      const data = await response.json();
      if (!Array.isArray(data) || data.length === 0) throw new Error('仓库暂无 Release');

      const parsed = [];
      data.forEach(rel => {
        const tag = rel.tag_name || '';
        const assets = rel.assets || [];

        let info = null;
        for (const a of assets) {
          info = parseAssetName(a.name);
          if (info) break;
        }
        const dev = info ? info.device : inferDevice(tag);
        const variant = info ? info.variant : inferVariant(tag);
        const variantLabel = variant === 'modem-pro' ? 'Modem Pro 统一版' : (variant === 'next' ? 'QModem Next' : '经典 LuCI');

        const primaryFile = dev === 'X86'
          ? assets.find(a => a.name.endsWith('-combined-efi.img.gz'))
          : assets.find(a => a.name.endsWith('-sysupgrade.bin'));
        const primary = primaryFile
          ? { name: primaryFile.name, size: primaryFile.size, download_url: primaryFile.browser_download_url }
          : null;

        const extras = [];
        if (dev === 'X86') {
          assets.forEach(a => {
            const n = a.name;
            if (primaryFile && n === primaryFile.name) return;
            const base = { name: n, size: a.size, download_url: a.browser_download_url };
            if (n.endsWith('-combined-efi.vmdk')) extras.push({ ...base, format: 'VMDK', title: 'VMware · UEFI' });
            else if (n.endsWith('-combined.vmdk')) extras.push({ ...base, format: 'VMDK', title: 'VMware · Legacy BIOS' });
            else if (n.endsWith('-image-efi.iso')) extras.push({ ...base, format: 'ISO', title: 'ISO 安装盘 · UEFI' });
            else if (n.endsWith('-image.iso')) extras.push({ ...base, format: 'ISO', title: 'ISO 安装盘 · Legacy BIOS' });
            else if (n.endsWith('-combined.img.gz')) extras.push({ ...base, format: 'BIOS', title: 'Legacy BIOS 磁盘镜像' });
          });
        }

        parsed.push({
          tag_name: tag,
          name: rel.name || tag,
          published_at: rel.published_at || new Date().toISOString(),
          device: dev,
          variant,
          build_date: info ? info.date : '',
          config: info ? info.config : '',
          description: dev === 'H5000M'
            ? `Hiveton H5000M 5G CPE · ${variantLabel} 前端 · Wi-Fi 7 (160MHz) · 双温感风扇调速`
            : (dev === 'AP3000M'
                ? `AirPi AP3000M · Wi-Fi 6 (160MHz) · ${variantLabel} · 开机自动写入 EEPROM 校准修复`
                : `x86_64 通用架构 · ${variantLabel} · 支持 UEFI / BIOS / VMware / ISO`),
          primary_asset: primary,
          extra_assets: extras
        });
      });

      if (parsed.length === 0) throw new Error('未解析出可用固件');
      allReleases = parsed;
      cloudState = 'ok';
      if (statusEl) statusEl.textContent = `已同步 ${parsed.length} 个云端 Release`;
      renderReleases();
    } catch (err) {
      console.warn('云端 Release 获取失败:', err);
      cloudState = 'error';
      cloudErrorMsg = err?.message || '未知错误';
      if (statusEl) statusEl.textContent = '云端 Release 获取失败';
      renderReleases();
    } finally {
      if (btnText) btnText.textContent = '刷新云端 Release';
    }
  }

  let toastTimer = null;
  function showToast(msg) {
    const toast = document.getElementById('toast');
    if (!toast) return;
    toast.textContent = msg;
    toast.classList.add('show');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => toast.classList.remove('show'), 2600);
  }

  function copyText(text, label = '内容') {
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text)
        .then(() => showToast(`已复制${label}`))
        .catch(() => fallbackCopy(text, label));
    } else {
      fallbackCopy(text, label);
    }
  }

  function fallbackCopy(text, label) {
    const ta = document.createElement('textarea');
    ta.value = text;
    ta.style.position = 'fixed';
    ta.style.opacity = '0';
    document.body.appendChild(ta);
    ta.select();
    try {
      document.execCommand('copy');
      showToast(`已复制${label}`);
    } catch {
      showToast('复制失败，请手动复制');
    }
    document.body.removeChild(ta);
  }

  window.appCopy = copyText;
  window.appFetchReleases = fetchLiveReleases;
  window.appToggleExtra = (idx) => {
    document.getElementById(`extraAssets-${idx}`)?.classList.toggle('open');
  };

  function initWallpaperControls() {
    const toggleBtn = document.getElementById('wallpaperToggleBtn');
    const panel = document.getElementById('wallpaperPanel');
    const blurSlider = document.getElementById('blurSlider');
    const blurVal = document.getElementById('blurValLabel');
    const alphaSlider = document.getElementById('alphaSlider');
    const alphaVal = document.getElementById('alphaValLabel');
    const zenBtn = document.getElementById('zenModeBtn');
    const zenExitBtn = document.getElementById('zenExitBtn');

    if (toggleBtn && panel) {
      toggleBtn.addEventListener('click', e => {
        e.stopPropagation();
        panel.classList.toggle('open');
      });
      document.addEventListener('click', e => {
        if (!panel.contains(e.target) && e.target !== toggleBtn) panel.classList.remove('open');
      });
    }

    document.querySelectorAll('.wp-thumb-btn').forEach(btn => {
      const idx = Number(btn.dataset.wpIndex);
      if (WALLPAPERS[idx] === window.currentWallpaperUrl) btn.classList.add('active');
      btn.addEventListener('click', () => {
        const url = WALLPAPERS[idx];
        if (!url) return;
        window.currentWallpaperUrl = url;
        document.documentElement.style.setProperty('--wallpaper-url', `url('${url}')`);
        document.querySelectorAll('.wp-thumb-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        showToast(`已切换至壁纸 ${idx + 1}`);
      });
    });

    document.querySelectorAll('.wp-mode-btn').forEach(btn => {
      btn.addEventListener('click', () => {
        const mode = btn.dataset.overlayMode;
        document.body.setAttribute('data-overlay', mode);
        document.querySelectorAll('.wp-mode-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        document.documentElement.style.removeProperty('--wallpaper-blur');
        document.documentElement.style.removeProperty('--card-alpha');
        const names = { standard: '标准轻透白底', clear: '极简纯白高对比', vibrant: '沉浸壁纸透视' };
        showToast(`外观模式：${names[mode] || mode}`);
      });
    });

    if (blurSlider && blurVal) {
      blurSlider.addEventListener('input', e => {
        const v = e.target.value;
        document.documentElement.style.setProperty('--wallpaper-blur', `${v}px`);
        blurVal.textContent = `${v}px`;
      });
    }

    if (alphaSlider && alphaVal) {
      alphaSlider.addEventListener('input', e => {
        const v = e.target.value;
        document.documentElement.style.setProperty('--card-alpha', (v / 100).toFixed(2));
        alphaVal.textContent = `${v}%`;
      });
    }

    const toggleZen = (enable) => {
      const next = typeof enable === 'boolean' ? enable : !document.body.classList.contains('zen-mode');
      document.body.classList.toggle('zen-mode', next);
      if (panel) panel.classList.remove('open');
      if (next) showToast('已进入纯享壁纸模式，按 ESC 退出');
    };

    if (zenBtn) zenBtn.addEventListener('click', () => toggleZen(true));
    if (zenExitBtn) zenExitBtn.addEventListener('click', () => toggleZen(false));
    window.addEventListener('keydown', e => {
      if (e.key === 'Escape' && document.body.classList.contains('zen-mode')) toggleZen(false);
    });
  }

  document.addEventListener('DOMContentLoaded', () => {
    const mobileBtn = document.getElementById('mobileMenuBtn');
    const navLinks = document.getElementById('navLinks');
    if (mobileBtn && navLinks) {
      mobileBtn.addEventListener('click', () => navLinks.classList.toggle('open'));
      navLinks.querySelectorAll('a').forEach(a => a.addEventListener('click', () => navLinks.classList.remove('open')));
    }

    const mirrorSelector = document.getElementById('mirrorSelector');
    if (mirrorSelector) {
      mirrorSelector.addEventListener('click', e => {
        const btn = e.target.closest('.segment-btn');
        if (!btn) return;
        mirrorSelector.querySelectorAll('.segment-btn').forEach(b => b.classList.remove('active'));
        btn.classList.add('active');
        currentMirror = btn.dataset.mirror;
        renderReleases();
        showToast(`已切换下载源：${btn.textContent}`);
      });
    }

    document.querySelectorAll('.chip[data-device]').forEach(chip => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('.chip[data-device]').forEach(c => c.classList.remove('active'));
        chip.classList.add('active');
        currentDeviceFilter = chip.dataset.device;
        renderReleases();
      });
    });

    document.querySelectorAll('.chip[data-variant]').forEach(chip => {
      chip.addEventListener('click', () => {
        document.querySelectorAll('.chip[data-variant]').forEach(c => c.classList.remove('active'));
        chip.classList.add('active');
        currentVariantFilter = chip.dataset.variant;
        renderReleases();
      });
    });

    const searchInput = document.getElementById('searchInput');
    if (searchInput) {
      searchInput.addEventListener('input', e => {
        searchQuery = e.target.value.trim().toLowerCase();
        renderReleases();
      });
    }

    initWallpaperControls();
    fetchLiveReleases();
  });
})();
