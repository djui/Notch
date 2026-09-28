(() => {
  const reduceMotion = matchMedia('(prefers-reduced-motion: reduce)').matches;

  // ---------- Notch demo ----------
  // [width, height, bottom radius] in container-query units of the screen.
  const shapes = {
    idle: [17, 3.3, 1.1],
    music: [31, 3.3, 1.1],
    agent: [32, 3.3, 1.1],
    charging: [30, 3.3, 1.1],
    focus: [29, 3.3, 1.1],
    meeting: [32, 3.3, 1.1],
    airpods: [30, 3.3, 1.1],
    'music-x': [44, 18.6, 3.4],
    'agent-x': [46, 21.4, 3.4],
    'meeting-x': [40, 10.6, 3.2],
  };

  const scenes = {
    music: [['music', 1500], ['music-x', 3800], ['music', 1200]],
    agent: [['agent', 1700], ['agent-x', 4600]],
    charging: [['charging', 2800]],
    meeting: [['meeting', 1600], ['meeting-x', 3200]],
    focus: [['focus', 2600]],
    airpods: [['airpods', 2600]],
  };
  const order = Object.keys(scenes);
  const expandedOf = { music: 'music-x', agent: 'agent-x', meeting: 'meeting-x' };
  const GAP = 450;

  const notch = document.getElementById('notch');
  const chips = document.querySelector('.chips');
  const layers = notch ? [...notch.querySelectorAll('.n-layer')] : [];

  let sceneIndex = 0;
  let timer = null;
  let hovering = false;

  function setShape(state) {
    const [w, h, r] = shapes[state];
    notch.style.setProperty('--w', w);
    notch.style.setProperty('--h', h);
    notch.style.setProperty('--r', r);
    notch.classList.toggle('open', state.endsWith('-x'));
    for (const layer of layers) layer.classList.toggle('on', layer.dataset.for === state);
  }

  function selectChip(name, duration) {
    for (const chip of chips.querySelectorAll('.chip')) {
      const active = chip.dataset.scene === name;
      chip.setAttribute('aria-selected', 'false');
      if (active) {
        chip.style.setProperty('--dur', duration + 'ms');
        void chip.offsetWidth; // restart the progress animation
        chip.setAttribute('aria-selected', 'true');
      }
    }
  }

  function playScene(index) {
    clearTimeout(timer);
    sceneIndex = (index + order.length) % order.length;
    const name = order[sceneIndex];
    const steps = scenes[name];
    const total = steps.reduce((sum, [, ms]) => sum + ms, 0);
    selectChip(name, total);

    let i = 0;
    const next = () => {
      if (i < steps.length) {
        const [state, ms] = steps[i++];
        setShape(state);
        timer = setTimeout(next, ms);
      } else {
        setShape('idle');
        timer = setTimeout(() => playScene(sceneIndex + 1), GAP);
      }
    };
    next();
  }

  if (notch && chips) {
    setShape('idle');

    chips.addEventListener('click', (e) => {
      const chip = e.target.closest('.chip');
      if (!chip) return;
      playScene(order.indexOf(chip.dataset.scene));
    });

    notch.addEventListener('mouseenter', () => {
      hovering = true;
      clearTimeout(timer);
      chips.classList.add('paused');
      const name = order[sceneIndex];
      setShape(expandedOf[name] || name);
    });
    notch.addEventListener('mouseleave', () => {
      hovering = false;
      chips.classList.remove('paused');
      setShape(order[sceneIndex]);
      timer = setTimeout(() => playScene(sceneIndex + 1), 900);
    });
    notch.addEventListener('click', () => {
      const name = order[sceneIndex];
      setShape(expandedOf[name] || name);
    });

    // Start once the hero is on screen, and pause while it is not.
    const stage = document.querySelector('.stage');
    let started = false;
    new IntersectionObserver(([entry]) => {
      if (entry.isIntersecting) {
        if (!started) { started = true; timer = setTimeout(() => playScene(0), 900); }
        else if (!hovering && !timer) playScene(sceneIndex);
      } else if (started) {
        clearTimeout(timer);
        timer = null;
      }
    }, { threshold: 0.15 }).observe(stage);
  }

  // ---------- Ticking timers ----------
  const fmt = (s) => `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`;
  const counters = [...document.querySelectorAll('[data-timer]')].map((el) => ({ el, s: +el.dataset.timer, dir: 1 }));
  const countdowns = [...document.querySelectorAll('[data-countdown]')].map((el) => ({ el, s: +el.dataset.countdown, start: +el.dataset.countdown, dir: -1 }));
  setInterval(() => {
    for (const c of counters) c.el.textContent = fmt(++c.s);
    for (const c of countdowns) { c.s = c.s <= 0 ? c.start : c.s - 1; c.el.textContent = fmt(c.s); }
  }, 1000);

  // ---------- Reveal on scroll ----------
  const reveals = document.querySelectorAll('.reveal');
  if (reduceMotion || !('IntersectionObserver' in window)) {
    reveals.forEach((el) => el.classList.add('in'));
  } else {
    const io = new IntersectionObserver((entries) => {
      for (const entry of entries) {
        if (entry.isIntersecting) { entry.target.classList.add('in'); io.unobserve(entry.target); }
      }
    }, { rootMargin: '0px 0px -8% 0px', threshold: 0.08 });
    reveals.forEach((el) => io.observe(el));
  }

  // ---------- Nav border ----------
  const nav = document.querySelector('.nav');
  const onScroll = () => nav.classList.toggle('scrolled', scrollY > 8);
  addEventListener('scroll', onScroll, { passive: true });
  onScroll();

  // ---------- Card spotlight ----------
  for (const card of document.querySelectorAll('.card')) {
    card.addEventListener('pointermove', (e) => {
      const r = card.getBoundingClientRect();
      card.style.setProperty('--mx', `${e.clientX - r.left}px`);
      card.style.setProperty('--my', `${e.clientY - r.top}px`);
    });
  }

  // ---------- Copy ----------
  for (const btn of document.querySelectorAll('[data-copy]')) {
    btn.addEventListener('click', async () => {
      const text = document.querySelector(btn.dataset.copy).textContent.trim();
      const label = btn.querySelector('span');
      try {
        await navigator.clipboard.writeText(text);
        btn.classList.add('done');
        label.textContent = 'Copied';
      } catch {
        label.textContent = 'Press ⌘C';
      }
      setTimeout(() => { btn.classList.remove('done'); label.textContent = 'Copy'; }, 1800);
    });
  }

  // ---------- Latest release ----------
  fetch('https://api.github.com/repos/djui/Notch/releases/latest', { headers: { Accept: 'application/vnd.github+json' } })
    .then((r) => (r.ok ? r.json() : null))
    .then((release) => {
      if (!release) return;
      const version = release.tag_name.replace(/^v/, '');
      const zip = (release.assets || []).find((a) => a.name.endsWith('.zip'));
      document.querySelectorAll('[data-version]').forEach((el) => { el.textContent = `Version ${version}`; });
      if (zip) {
        document.querySelectorAll('[data-download]').forEach((a) => { a.href = zip.browser_download_url; });
        document.querySelectorAll('[data-zip]').forEach((el) => { el.textContent = zip.name; });
      }
    })
    .catch(() => {});
})();
