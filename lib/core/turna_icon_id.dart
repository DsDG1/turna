/// 全 App 包豪斯几何图标语义枚举（ADR 0075）。
///
/// 纯 Dart 定义、零 Flutter 依赖：允许 `lib/domain/`、`lib/application/`、
/// `lib/core/` 与 `lib/views/` 共同消费，不再将 Material `IconData` 泄漏进
/// 领域层与应用层。
library;

enum TurnaIconId {
  // 1. Navigation & Chevrons
  arrowBack('arrow-back'),
  arrowForward('arrow-forward'),
  chevronRight('chevron-right'),
  chevronDown('chevron-down'),
  chevronUp('chevron-up'),
  moveUp('move-up'),
  moveDown('move-down'),
  openInNew('open-in-new'),
  close('close'),
  moreVert('more-vert'),
  dragHandle('drag-handle'),
  swapArrows('swap-arrows'),

  // 2. Actions & Editing
  add('add'),
  edit('edit'),
  delete('delete'),
  deleteSweep('delete-sweep'),
  copy('copy'),
  save('save'),
  share('share'),
  search('search'),
  filter('filter'),
  refresh('refresh'),
  restart('restart'),
  restore('restore'),
  undo('undo'),
  redo('redo'),
  send('send'),
  pin('pin'),
  bookmark('bookmark'),
  logout('logout'),

  // 3. Media & Audio
  play('play'),
  pause('pause'),
  stop('stop'),
  speaker('speaker'),
  headphones('headphones'),
  mic('mic'),
  speakVoice('speak-voice'),
  waveform('waveform'),
  repeat('repeat'),
  speed('speed'),

  // 4. Selection & Status
  check('check'),
  checkCircle('check-circle'),
  cancel('cancel'),
  warning('warning'),
  error('error'),
  info('info'),
  help('help'),
  lock('lock'),
  keyOff('key-off'),
  verified('verified'),
  shield('shield'),
  radioChecked('radio-checked'),
  radioUnchecked('radio-unchecked'),
  checkboxChecked('checkbox-checked'),
  checkboxUnchecked('checkbox-unchecked'),
  eye('eye'),
  eyeOff('eye-off'),

  // 5. Learning, Language & AI
  book('book'),
  school('school'),
  cards('cards'),
  layers('layers'),
  tree('tree'),
  translate('translate'),
  spark('spark'),
  brain('brain'),
  lightbulb('lightbulb'),
  chat('chat'),
  article('article'),
  list('list'),
  flag('flag'),
  tag('tag'),
  target('target'),
  bolt('bolt'),

  // 6. Profile, Gamification & Nature/Cosmetics
  person('person'),
  flame('flame'),
  diamond('diamond'),
  star('star'),
  trophy('trophy'),
  landscape('landscape'),
  sunrise('sunrise'),
  sun('sun'),
  moon('moon'),
  leaf('leaf'),
  explore('explore'),

  // 7. Data, Charts, Files & System
  insights('insights'),
  timer('timer'),
  percent('percent'),
  folder('folder'),
  upload('upload'),
  download('download'),
  cloudOff('cloud-off'),
  wifi('wifi'),
  storage('storage'),
  image('image'),
  code('code'),
  wrench('wrench'),
  heartPulse('heart-pulse'),
  bug('bug'),
  palette('palette'),
  textSize('text-size'),
  accessibility('accessibility'),
  bell('bell');

  const TurnaIconId(this.slug);

  /// 对应 `assets/icons/<slug>.svg` 的文件名（不含后缀）。
  final String slug;

  /// Flutter 资产路径。
  String get assetPath => 'assets/icons/$slug.svg';
}
