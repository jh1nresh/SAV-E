(() => {
  const bar = document.querySelector('sakuga-progress');
  let started = false;
  window.savvyOpening = state => {
    const palette = state.dark
      ? {fill:'#302343',shade:'#8481F5',line:'#B6ACFF',accent:'#FCDDEA',ink:'#F1EAFD',sfx:['#F1EAFD','#302343']}
      : {fill:'#FFFAFD',shade:'#B6ACFF',line:'#4F43B9',accent:'#FCDDEA',ink:'#231835',sfx:['#231835','#FFFAFD']};
    Object.assign(window.SakugaFX.P,palette);
    bar.style.setProperty('--sk-fill',state.dark?'#8481F5':'#4F43B9');
    bar.style.setProperty('--sk-card',palette.fill);
    bar.style.setProperty('--sk-ink',palette.ink);
    bar.setAttribute('label',state.label || 'Opening animation');
    document.body.classList.toggle('calm',state.reduced);
    window.SakugaFX.paused = !state.active;
    if (!started) {
      started = true;
      // No demo attribute: the upstream animation runs once and never reverses.
      bar.set(1,state.reduced || state.elapsed >= 3);
    } else if(state.reduced) { bar.set(1,true); }
  };
})();