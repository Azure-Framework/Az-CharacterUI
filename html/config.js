window.AZFW_CONFIG = {
  // Logo content: plain text (single letters recommended) or small HTML string.
  logoText: 'SLS',

  // Brand text shown next to the logo
  brandTitle: 'State of Los Santos',
  brandSubtitle: 'All characters — choose or create',

  // Color palette (everything this UI uses)
  colors: {
    //
    // CORE THEME
    //
    bg0: '#050817',   // --bg-0   (main background top – deep navy)
    bg1: '#050b21',   // --bg-1   (main background bottom – slightly warmer navy)
    text: '#fdf7ff',  // main body text – soft off-white with a hint of magenta
    muted: '#9aa8d6', // subtitles, hints – desaturated blue/violet

    // Primary accents (used by logo, primary buttons, etc.)
    // Neon magenta + cyan to match the 3D logo gradient
    accent:  '#ff4da6', // --accent   (neon pink)
    accent2: '#42e0ff', // --accent-2 (neon cyan)

    //
    // PANELS / CARDS / GENERAL SURFACES
    //
    panelGradientTop:    'rgba(255,255,255,0.03)',
    panelGradientBottom: 'rgba(8,12,36,0.96)',
    panelBorder:         'rgba(255,255,255,0.05)',
    panelShadow:         '0 12px 48px rgba(0,0,0,0.75)',

    cardGradientTop:     'rgba(255,255,255,0.02)',
    cardGradientBottom:  'rgba(10,16,40,0.98)',
    cardBorder:          'rgba(255,255,255,0.05)',
    cardHoverShadow:     '0 14px 40px rgba(0,0,0,0.8)',

    // Selected card outlining / soft neon glow
    selectedOutline: 'rgba(255,77,166,0.28)',  // pink edge
    selectedShadow:  '0 22px 60px rgba(66,224,255,0.22)', // cyan glow

    // Avatar & stat pill surfaces
    avatarBorder:  'rgba(255,255,255,0.06)',
    statPillBg:    'rgba(255,255,255,0.02)',

    //
    // VIEWPORT / BIG LETTER AVATAR
    //
    viewportTop:    '#07152b', // darker navy with slight teal
    viewportBottom: '#04091c',
    viewportBorder: 'rgba(255,255,255,0.05)',

    //
    // MODALS (create/edit/delete/confirm)
    //
    modalBackdropBg: 'rgba(5,8,20,0.92)',
    modalBgTop:      'rgba(12,18,46,0.98)',
    modalBgBottom:   'rgba(4,7,24,0.98)',
    modalBorder:     'rgba(66,224,255,0.35)',   // cyan edge
    modalShadow:     '0 18px 60px rgba(0,0,0,0.9)',
    modalHeader:     '#ff82c8',                 // modal title – lighter neon pink

    //
    // SPAWN MODAL + MAP
    //
    spawnBgTop:    '#04091c',
    spawnBgBottom: '#030814',
    spawnBorder:   'rgba(255,255,255,0.04)',
    spawnShadow:   '0 30px 90px rgba(0,0,0,0.8)',

    spawnMapTop:    '#071829',
    spawnMapBottom: '#030814',
    spawnMapBorder: 'rgba(255,255,255,0.04)',

    //
    // SPAWN PINS (map markers)
    //
    pin:             '#ff4da6',                            // base pin color (neon pink)
    pinBorder:       '#42e0ff',                            // cyan ring
    pinShadow:       '0 6px 18px rgba(0,0,0,0.6)',
    pinActiveHalo:   'rgba(66,224,255,0.18)',              // cyan halo
    pinActiveShadow: '0 8px 22px rgba(0,0,0,0.65)',

    //
    // SPAWN LIST (right side list)
    //
    spawnListBg:         'rgba(255,255,255,0.02)',
    spawnSelectedBg:     'rgba(66,224,255,0.10)', // subtle cyan strip
    spawnSelectedBorder: 'var(--accent)',         // left border on selected item (neon pink)

    //
    // ZOOM BUTTONS
    //
    zoomBg:        'rgba(0,0,0,0.45)',
    zoomBorder:    'rgba(255,255,255,0.06)',
    zoomHoverBg:   'rgba(255,255,255,0.05)',
    zoomText:      'var(--muted)',
    zoomHoverText: 'var(--accent)',

    //
    // SCROLLBARS
    //
    scrollThumbBg: 'rgba(255,255,255,0.06)',

    //
    // TOASTS
    //
    toastBg:     'rgba(2,4,12,0.9)',
    toastText:   '#fdf7ff',
    toastBorder: 'rgba(255,255,255,0.06)',
    toastShadow: '0 6px 24px rgba(0,0,0,0.75)',

    //
    // GUIDE OVERLAY
    //
    guidePanelBgTop:     'rgba(255,255,255,0.03)',
    guidePanelBgBottom:  'rgba(3,5,18,0.96)',
    guidePanelBorder:    'rgba(255,255,255,0.06)',
    guidePanelShadow:    '0 18px 60px rgba(0,0,0,0.8)',

    guideTooltipBgTop:    '#07152b',
    guideTooltipBgBottom: '#04091c',
    guideTooltipBorder:   'rgba(255,255,255,0.06)',
    guideTooltipShadow:   '0 12px 40px rgba(0,0,0,0.75)',

    guideHighlightOutline: 'rgba(255,77,166,0.3)',   // pink highlight
    guideHighlightShadow:  '0 14px 40px rgba(66,224,255,0.2)' // cyan glow
  }
};
