// EVERY KEY, IN PLAIN LANGUAGE.
//
// The wording half of the settings substrate (ISSUES 9.1). One entry per key:
// what it is called in words, what it does and where it acts, and the range it
// ordinarily rides. Keys that say the same thing about different surfaces are
// NOT here -- they are one family entry in `settings_words.dart`, said once.
//
// A key with no entry and no family is a key nobody said anything about, and
// the wording light refuses it by name. That is the point: coverage is proved,
// not claimed.

import 'settings_words.dart';

const Map<String, SettingSaid> settingVocabulary = {
  // --- How much fits in a cell ---------------------------------------------
  'capacity.floor': SettingSaid(
    'Fewest marks a cell keeps',
    'However tight a cell gets, it keeps at least this many marks and reports '
        'the rest as a count. A cell that showed nothing would be a lie about '
        'an empty day.',
    low: '1',
    high: '20',
  ),
  'capacity.markHeight': SettingSaid(
    'Room one mark needs, down',
    'How tall a mark is assumed to be when a cell works out how many of them '
        'will fit, in pixels.',
    low: '8',
    high: '48',
  ),
  'capacity.markWidth': SettingSaid(
    'Mark width',
    'How wide a mark is assumed to be when a cell works out how many of them '
        'will fit, in pixels.',
    low: '20',
    high: '240',
  ),
  'capacity.queryMultiple': SettingSaid(
    'How much more to ask for',
    'A lens asks the document for this many times the marks it can draw, so it '
        'knows there are more and can say so instead of implying a full view.',
    low: '1',
    high: '8',
  ),
  'capacity.stackDepth': SettingSaid(
    'Marks stacked before a count',
    'How many marks may pile on one point before the pile becomes a number.',
    low: '1',
    high: '12',
  ),

  // --- The cards ------------------------------------------------------------
  'card.closeVerb': SettingSaid(
    'What the X on a card does',
    'The word one of the card verbs wears: save writes and closes, apply writes '
        'and closes, discard throws the edit away as its own undo entry. A word '
        'no card offers is refused in words rather than guessed at.',
  ),
  'card.controlMin': SettingSaid(
    'Narrowest a control may be',
    'Below this much room a card row drops its label onto a tooltip and gives '
        'the whole width to the control, in pixels.',
    low: '20',
    high: '160',
  ),
  'card.fieldWidth': SettingSaid(
    'Width of a text box',
    'How wide an ordinary text box on a card is, in pixels.',
    low: '80',
    high: '480',
  ),
  'card.findRows': SettingSaid(
    'Rows a find offers',
    'How many rows a card list will draw before it asks you to narrow the find. '
        'A workspace may hold five hundred frames; nothing here enumerates them.',
    low: '10',
    high: '1000',
  ),
  'card.gap': SettingSaid(
    'Space between things on a card',
    'The one gap every card uses between a control and its neighbour, in pixels.',
    low: '2',
    high: '24',
  ),
  'card.labelMin': SettingSaid(
    'Narrowest a label may be',
    'Below this much room a row stacks its label above its control instead of '
        'beside it, in pixels.',
    low: '20',
    high: '160',
  ),
  'card.labelShare': SettingSaid(
    'Share of a row the label takes',
    'How much of a card row goes to the label when there is room for both, as a '
        'fraction of the row.',
    low: '0',
    high: '1',
  ),
  'card.labelWidth': SettingSaid(
    'Widest a label gets',
    'A card label never grows past this, however wide the card is, in pixels.',
    low: '40',
    high: '320',
  ),
  'card.listHeight': SettingSaid(
    'Height of a list on a card',
    'How tall a scrolling list inside a card stands, in pixels.',
    low: '80',
    high: '900',
  ),
  'card.narrowWidth': SettingSaid(
    'Width of a small number box',
    'How wide a box holding one number — a count, an interval — is, in pixels.',
    low: '30',
    high: '200',
  ),
  'card.newFrameTraits': SettingSaid(
    'What a new frame starts as',
    'The traits a brand-new frame card opens holding, written as words with '
        'spaces between them. A starting point, not a species: every trait is '
        'authored on the card and any of them can be taken back off.',
  ),
  'card.noteLines': SettingSaid(
    'Lines a note body gets',
    'How many lines of room the description gets when the object is a note, so '
        'the body reads as a body.',
    low: '3',
    high: '40',
  ),
  'card.pad': SettingSaid(
    'Padding inside a card',
    'The breathing room between a card\'s edge and its contents, in pixels.',
    low: '0',
    high: '40',
  ),
  'card.palette': SettingSaid(
    'Colours the picker offers',
    'The colour names the picker puts in front of you, written with spaces '
        'between them. The field still takes any name or hex you know; this is '
        'the short way in.',
  ),
  'card.pickerHeight': SettingSaid(
    'Height of a find drop',
    'How tall the drop under a find box stands, in pixels.',
    low: '60',
    high: '600',
  ),
  'card.pickerWidth': SettingSaid(
    'Width of a find drop',
    'How wide the drop under a find box stands, in pixels.',
    low: '60',
    high: '600',
  ),
  'card.railSteps': SettingSaid(
    'How finely a number line lands',
    'How many places a settings number line offers between its two ends. The '
        'number you click through to takes any value at all.',
    low: '10',
    high: '10000',
  ),
  'card.pickerGrip': SettingSaid(
    'Size of a picker handle',
    'How large the grab handle on the colour field and the hue track is drawn, '
        'in pixels.',
    low: '6',
    high: '30',
  ),
  'card.regionHeight': SettingSaid(
    'How tall a region of sentences gets',
    'How much room the sentences on a card take before that region rides its '
        'own scroll, in pixels. The header above it never moves, so an object '
        'with two hundred staples costs the same height as one with two.',
    low: '120',
    high: '1200',
  ),
  'card.rowHeight': SettingSaid(
    'Height of a list row',
    'How tall one row of a card list stands, in pixels.',
    low: '16',
    high: '80',
  ),
  'card.searchScan': SettingSaid(
    'How far a find looks',
    'How many records a find will walk before it stops and reports the rest as '
        'a lower bound. Overscale: nothing ever reads the whole document to '
        'fill a dropdown.',
    low: '100',
    high: '20000',
  ),
  'card.searchWindow': SettingSaid(
    'Hits a find lists',
    'How many matches a find shows at once; whatever else it saw is reported as '
        'a count, never dropped in silence.',
    low: '3',
    high: '60',
  ),
  'card.sigil': SettingSaid(
    'Size of the card\'s glyph',
    'How large the little mark beside a card\'s title is drawn, in pixels.',
    low: '8',
    high: '40',
  ),
  'card.stapledDistance': SettingSaid(
    'How far "stapled here" looks',
    'A neighbourhood is a distance. One shows what is stapled directly to this; '
        'two shows their neighbours too, and so on. Every card offers the '
        'number, so nothing decides the reach for you.',
    low: '1',
    high: '8',
  ),
  'card.swatch': SettingSaid(
    'Size of a colour swatch',
    'How large a colour square on a card is, in pixels.',
    low: '10',
    high: '60',
  ),
  'card.textLines': SettingSaid(
    'Lines a description gets',
    'How many lines of room an ordinary description field gets before it '
        'scrolls.',
    low: '1',
    high: '20',
  ),

  // --- The bars -------------------------------------------------------------
  'chrome.activeWash': SettingSaid(
    'Tint on the choice in force',
    'How strongly the control you are actually using is tinted, from clear to '
        'solid.',
    low: '0',
    high: '1',
  ),
  'chrome.barHeight': SettingSaid(
    'Height of a bar',
    'How tall a bar stands before its own contents push it taller, in pixels.',
    low: '16',
    high: '80',
  ),
  'chrome.body': SettingSaid(
    'Reading size',
    'The size ordinary words are set in across the whole surface, in pixels. '
        'Every other size is derived from it.',
    low: '9',
    high: '24',
  ),
  'chrome.corner': SettingSaid(
    'Corner rounding',
    'How rounded the corner of a control or a panel is, in pixels.',
    low: '0',
    high: '16',
  ),
  'chrome.focusRing': SettingSaid(
    'Thickness of the selection ring',
    'How thick the ring around the thing you have chosen is drawn, in pixels.',
    low: '1',
    high: '6',
  ),
  'chrome.frameRows': SettingSaid(
    'Frames a drop shows',
    'How many frames the projection drop lists before it asks you to narrow the '
        'find.',
    low: '4',
    high: '60',
  ),
  'chrome.gap': SettingSaid(
    'Space between controls',
    'The gap between one control on a bar and the next, in pixels.',
    low: '0',
    high: '24',
  ),
  'chrome.hair': SettingSaid(
    'Thickness of a hairline',
    'Every rule, border and divider in the chrome is drawn this thick, in '
        'pixels.',
    low: '0.5',
    high: '4',
  ),
  'chrome.hit': SettingSaid(
    'Smallest thing you can hit',
    'The least height any control is given, so nothing is too small to click, '
        'in pixels.',
    low: '16',
    high: '56',
  ),
  'chrome.hoverWash': SettingSaid(
    'Tint under the pointer',
    'How strongly a control lights up when the pointer is over it, from clear '
        'to solid.',
    low: '0',
    high: '1',
  ),
  'chrome.label': SettingSaid(
    'Label size',
    'The size the small words naming a control are set in, in pixels.',
    low: '7',
    high: '20',
  ),
  'chrome.labelCap': SettingSaid(
    'Longest a label runs',
    'Past this many characters a bar label is shortened rather than pushing '
        'everything else off the bar.',
    low: '8',
    high: '80',
  ),
  'chrome.menuWidth': SettingSaid(
    'Width of a menu',
    'How wide a drop-down or right-click menu stands, in pixels.',
    low: '120',
    high: '600',
  ),
  'chrome.pad': SettingSaid(
    'Padding inside a control',
    'The room between a control\'s edge and the word inside it, in pixels.',
    low: '0',
    high: '24',
  ),
  'chrome.readingWidth': SettingSaid(
    'How wide a reading may get',
    'The widest, in pixels, that a drop-down showing a READING — the frames '
        'this view projects, written out — may draw on a bar. A reading grows '
        'with the document and the bar does not, so past this width it is '
        'trimmed with an ellipsis and read in full inside the drop.',
    low: '80',
    high: '600',
  ),
  'chrome.rowHeight': SettingSaid(
    'Height of a menu row',
    'How tall one row of a menu stands, in pixels.',
    low: '16',
    high: '64',
  ),
  'chrome.title': SettingSaid(
    'Title size',
    'The size a card\'s or a window\'s name is set in, in pixels.',
    low: '10',
    high: '32',
  ),
  'chrome.unit': SettingSaid(
    'The chrome\'s grain',
    'The one number the bar sizes are built out of: change it and the whole '
        'chrome coarsens or tightens together.',
    low: '1',
    high: '6',
  ),

  // --- The curve view -------------------------------------------------------
  'curve.arcMinimum': SettingSaid(
    'Smallest arc worth drawing',
    'A stretch of curve shorter than this share of the whole is left out rather '
        'than drawn as a smudge.',
    low: '0',
    high: '1',
  ),
  'curve.bandOpacity': SettingSaid(
    'Solidity of the band',
    'How solid the soft band around the curve is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'curve.coreOpacity': SettingSaid(
    'Solidity of the core',
    'How solid the curve\'s own line is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'curve.labelBudget': SettingSaid(
    'Labels along the curve',
    'How many labels the curve draws before it starts thinning them.',
    low: '2',
    high: '80',
  ),
  'curve.labelDecimals': SettingSaid(
    'Decimals in a curve label',
    'How many digits past the point a value beside the curve is written with.',
    low: '0',
    high: '6',
  ),
  'curve.labelOffset': SettingSaid(
    'Gap under a curve label',
    'How far a label sits from the point it names, in pixels.',
    low: '0',
    high: '40',
  ),
  'curve.laneShare': SettingSaid(
    'Share of the lane the curve takes',
    'How much of its lane\'s height the curve is allowed to swing through, as a '
        'fraction.',
    low: '0',
    high: '1',
  ),
  'curve.margin': SettingSaid(
    'Room around the curve',
    'The blank room kept around the curve so its extremes are not against the '
        'edge, in pixels.',
    low: '0',
    high: '120',
  ),

  // --- The document ---------------------------------------------------------
  'document.compactMinutes': SettingSaid(
    'Minutes before the journal is folded',
    'The journal folds entries older than this into one, so a long session does '
        'not accrue a file of keystrokes.',
    low: '1',
    high: '240',
  ),
  'document.icsPaths': SettingSaid(
    'Where calendars are looked for',
    'One location per line — a folder lists the .ics files in it, a file is '
        'that file. As many as you keep calendars in; empty means beside the '
        'app.',
  ),
  'document.lamp': SettingSaid(
    'Size of the saved lamp',
    'How large the little lamp that says whether the document is written down '
        'is drawn, in pixels.',
    low: '4',
    high: '24',
  ),
  'document.saveAt': SettingSaid(
    'Where the document saves',
    'The folder this chronolog is written to. Empty means beside the app, which '
        'is the portable default; writing a path here moves the document.',
  ),
  'document.deleteWord': SettingSaid(
    'Word that arms deleting everything',
    'Type this word on the document card to arm the delete-all door. Until it '
        'is typed exactly, that door does nothing. Deleting everything is the '
        'one act here with no undo, which is why it asks you to say a word '
        'rather than click a box.',
  ),
  'document.saveGap': SettingSaid(
    'Space around the save lamp',
    'The gap between the save mark, its lamp and the word beside them, in '
        'pixels.',
    low: '0',
    high: '20',
  ),

  // --- Editing --------------------------------------------------------------
  'edit.groupFuzz': SettingSaid(
    'How close counts as together',
    'Two things within this much are treated as one group by the edits that '
        'work on a group.',
    low: '0',
    high: '20',
  ),
  'edit.historyDepth': SettingSaid(
    'Steps of undo kept',
    'How many edits back you can walk. Nothing here ever asks before doing '
        'something, so this is what makes that safe.',
    low: '10',
    high: '2000',
  ),
  'edit.newPointFar': SettingSaid(
    'Where a new sentence touches the other thing',
    'Which point of the far object a sentence you start touches by default — '
        'its start, its end, its midpoint, or the whole of it. Say another and '
        'the row shows it before it writes it.',
  ),
  'edit.newPointNear': SettingSaid(
    'Where a new sentence touches this thing',
    'Which point of the object you are editing a sentence you start touches by '
        'default. Stapling the end of this to the start of that is one word '
        'away in each of the two keys.',
  ),
  'edit.newSpanDays': SettingSaid(
    'How long a new thing lasts',
    'The span a freshly minted object claims, in days, and the step Push '
        'forward moves a placement by.',
    low: '0',
    high: '30',
  ),
  'edit.pasteStepDays': SettingSaid(
    'How far a pasted copy lands',
    'How far a keyboard duplicate sits from the thing it was duplicated from, '
        'in days. A twin exactly on its source draws as one mark, so the paste '
        'steps -- and how far it steps is yours.',
    low: '0',
    high: '30',
  ),
  'edit.snapGrainMinutes': SettingSaid(
    'What a drag snaps to',
    'Dragging on a time surface lands on this grain, in minutes.',
    low: '1',
    high: '120',
  ),

  // --- The month grid -------------------------------------------------------
  'grid.chipDepth': SettingSaid(
    'Chips stacked in a day',
    'How many chips may overlap in one day cell before the rest become a count.',
    low: '1',
    high: '8',
  ),
  'grid.chipHeight': SettingSaid(
    'Height of a day chip',
    'How tall one chip inside a day cell stands, in pixels.',
    low: '6',
    high: '40',
  ),
  'grid.chipWidth': SettingSaid(
    'Width of a day chip',
    'How wide one chip inside a day cell runs, in pixels.',
    low: '20',
    high: '240',
  ),
  'grid.drawOrder': SettingSaid(
    'What order a day cell reads in',
    'Display weight decides which chips fit a crowded cell; this decides where '
        'the survivors stand. Positive reads earliest first, negative reads '
        'latest first.',
    low: '-1',
    high: '1',
  ),
  'grid.gutter': SettingSaid(
    'Width of the week gutter',
    'The strip down the side of the grid where week names stand, in pixels.',
    low: '0',
    high: '200',
  ),
  'grid.header': SettingSaid(
    'Height of the weekday header',
    'The band across the top of the grid naming the days, in pixels.',
    low: '0',
    high: '60',
  ),
  'grid.labelSize': SettingSaid(
    'Size of a grid label',
    'The size the words on the month grid are set in, in pixels.',
    low: '6',
    high: '20',
  ),
  'grid.nameAt': SettingSaid(
    'Where a chip\'s name starts',
    'How far into a day cell the name of a thing begins, in pixels.',
    low: '0',
    high: '200',
  ),
  'grid.numberAt': SettingSaid(
    'Where the day number sits',
    'How far into a day cell the day number is drawn, in pixels.',
    low: '0',
    high: '120',
  ),
  'grid.numberSize': SettingSaid(
    'Size of the day number',
    'The size a day\'s own number is set in, in pixels.',
    low: '6',
    high: '28',
  ),
  'grid.overflowSize': SettingSaid(
    'Size of the "and more" count',
    'The size the count of what did not fit in a cell is set in, in pixels.',
    low: '5',
    high: '20',
  ),
  'grid.pad': SettingSaid(
    'Padding inside a day cell',
    'The room between a day cell\'s edge and what it holds, in pixels.',
    low: '0',
    high: '20',
  ),
  'grid.pipSize': SettingSaid(
    'Size of a day pip',
    'The little dot standing for something too small to chip, in pixels.',
    low: '2',
    high: '20',
  ),
  'grid.pipStep': SettingSaid(
    'Space between day pips',
    'How far apart pips are set as they fill a day cell, in pixels. Pips with '
        'no name to carry flow across the cell and wrap, so this is how tightly '
        'a busy day packs.',
    low: '2',
    high: '30',
  ),
  'grid.rule': SettingSaid(
    'Thickness of the grid lines',
    'How thick the lines between day cells are drawn, in pixels.',
    low: '0',
    high: '6',
  ),
  'grid.slashPast': SettingSaid(
    'Strength of the past hatching',
    'How strongly a day already gone is hatched over, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'grid.spectrumSigil': SettingSaid(
    'Size of a to-do sigil',
    'How large the mark at each end of an unfinished to-do line is drawn on the '
        'month grid, in pixels.',
    low: '2',
    high: '20',
  ),
  'grid.spectrumWidth': SettingSaid(
    'Thickness of the to-do line',
    'How thick the dotted line between an unfinished to-do and now is drawn on '
        'the month grid, in pixels.',
    low: '0',
    high: '6',
  ),
  'grid.washPast': SettingSaid(
    'Wash over a past day',
    'How strongly a day already gone is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'grid.washSpectrum': SettingSaid(
    'Wash of the to-do line',
    'How strongly the line running from an unfinished to-do to now is drawn, '
        'from clear to solid.',
    low: '0',
    high: '1',
  ),
  'grid.washToday': SettingSaid(
    'Wash over today',
    'How strongly today\'s cell is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'grid.washWeekend': SettingSaid(
    'Wash over a weekend day',
    'How strongly a weekend cell is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'grid.weekendCount': SettingSaid(
    'How many weekend days',
    'How many of the weekend-day settings below the grid actually reads.',
    low: '0',
    high: '7',
  ),

  // --- The Intimate lens ----------------------------------------------------
  'intimate.back': SettingSaid(
    'Columns kept behind',
    'How many columns before the one you are looking at stay on screen.',
    low: '0',
    high: '10',
  ),
  'intimate.bleedViewports': SettingSaid(
    'Windows painted past each edge',
    'How much surface is drawn beyond the window on every side, counted in '
        'windows. A drag can be shown live only as far as something has already '
        'been painted, so one window means an ordinary drag never runs out of '
        'painted day. More is smoother and costs more to draw.',
    low: '0',
    high: '3',
  ),
  'intimate.edge': SettingSaid(
    'Strength of a block\'s edge',
    'How strongly the outline of a block is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'intimate.fill': SettingSaid(
    'Strength of a block\'s fill',
    'How strongly the inside of a block is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'intimate.floatShare': SettingSaid(
    'Share a floating block takes',
    'How much of a column a block that has nothing to sit beside occupies, as a '
        'fraction.',
    low: '0',
    high: '1',
  ),
  'intimate.floatWidth': SettingSaid(
    'Width of a floating block',
    'How wide a block with nothing beside it runs, in pixels.',
    low: '40',
    high: '400',
  ),
  'intimate.forward': SettingSaid(
    'Columns kept ahead',
    'How many columns past the one you are looking at stay on screen.',
    low: '0',
    high: '10',
  ),
  'intimate.grab': SettingSaid(
    'Width of the move strip',
    'The strip along a block\'s leading edge that grabs it, in pixels. The '
        'whole body moves a block; this is the edge you resize from.',
    low: '0',
    high: '40',
  ),
  'intimate.grain': SettingSaid(
    'What a drag lands on',
    'A drag on this lens lands on this grain, in minutes.',
    low: '1',
    high: '120',
  ),
  'intimate.hourPixels': SettingSaid(
    'Height of an hour',
    'How tall one hour stands on this lens, in pixels. This is the zoom.',
    low: '8',
    high: '400',
  ),
  'intimate.hourRule': SettingSaid(
    'Thickness of the hour line',
    'How thick the line at each hour is drawn, in pixels.',
    low: '0',
    high: '6',
  ),
  'intimate.labelSize': SettingSaid(
    'Size of a column label',
    'The size the name over a column is set in, in pixels.',
    low: '6',
    high: '24',
  ),
  'intimate.markMinHeight': SettingSaid(
    'Shortest a block gets',
    'However brief a thing is, its block is drawn at least this tall so it can '
        'still be read and grabbed, in pixels.',
    low: '2',
    high: '60',
  ),
  'intimate.midnightRule': SettingSaid(
    'Thickness of the day line',
    'How thick the line where one day becomes the next is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'intimate.minColumnPixels': SettingSaid(
    'Narrowest a column may be',
    'Below this the lens shows fewer days rather than shaving the columns, in '
        'pixels.',
    low: '40',
    high: '600',
  ),
  'intimate.pad': SettingSaid(
    'Padding inside a column',
    'The room between a column\'s edge and the blocks in it, in pixels.',
    low: '0',
    high: '20',
  ),
  'intimate.pip': SettingSaid(
    'Size of a pip',
    'The dot standing for something with no duration to draw, in pixels.',
    low: '2',
    high: '24',
  ),
  'intimate.preferMajor': SettingSaid(
    'The major spacing this lens prefers',
    'The ruler spacing this lens clings to, in hours of the day the frame '
        'itself declares. '
        'It yields only to a rung on its own ladder, so it never settles on a '
        'spacing nobody holds an opinion about.',
    low: '0.01',
    high: '24',
  ),
  'intimate.preferMinor': SettingSaid(
    'The minor spacing this lens prefers',
    'The finer ruler spacing this lens clings to, in hours of the day the frame '
        'itself declares, paired with the major above.',
    low: '0.01',
    high: '24',
  ),
  'intimate.radius': SettingSaid(
    'Rounding of a block',
    'How rounded the corners of a block are, in pixels.',
    low: '0',
    high: '16',
  ),
  'intimate.span': SettingSaid(
    'Days on screen in Intimate',
    'How many days Intimate shows at once before anything is said about it in '
        'the view. A control writes whatever the view itself says; this is what it '
        'falls back to.',
    low: '1',
    high: '31',
  ),
  'intimate.rail': SettingSaid(
    'Width of the time rail',
    'The strip down the side of the lens where the hours are written, in '
        'pixels.',
    low: '0',
    high: '200',
  ),
  'intimate.rule': SettingSaid(
    'Thickness of the column rule',
    'How thick the line between one column and the next is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'intimate.ruleLadderCount': SettingSaid(
    'Rungs on the ruler ladder',
    'How many of the ruler rungs below the lens actually reads.',
    low: '1',
    high: '40',
  ),
  'intimate.spectrumSigil': SettingSaid(
    'Size of a to-do sigil',
    'How large the mark at each end of an unfinished to-do line is drawn on '
        'this lens, in pixels.',
    low: '2',
    high: '20',
  ),
  'intimate.spectrumWidth': SettingSaid(
    'Thickness of the to-do line',
    'How thick the dotted line between an unfinished to-do and now is drawn on '
        'this lens, in pixels.',
    low: '0',
    high: '6',
  ),
  'intimate.timeSize': SettingSaid(
    'Size of a time on the rail',
    'The size an hour written down the rail is set in, in pixels.',
    low: '5',
    high: '20',
  ),
  'intimate.titleSize': SettingSaid(
    'Size of a block\'s name',
    'The size the name inside a block is set in, in pixels.',
    low: '6',
    high: '24',
  ),
  'intimate.washOverlap': SettingSaid(
    'Wash where blocks overlap',
    'How strongly the part where two blocks cross is tinted, from clear to '
        'solid.',
    low: '0',
    high: '1',
  ),
  'intimate.washSpectrum': SettingSaid(
    'Wash of the to-do line',
    'How strongly the line running from an unfinished to-do to now is drawn '
        'here, from clear to solid.',
    low: '0',
    high: '1',
  ),

  // --- The keyboard ---------------------------------------------------------
  'keys.alignSeams': SettingSaid(
    'See and lock the drag bars',
    'The key held to show every drag bar and author which of them move '
        'together. Without it a drag bar moves only the two windows it sits '
        'between.',
  ),
  'keys.closeTile': SettingSaid(
    'Close this window',
    'The chord that closes the window you are in.',
  ),
  'keys.delete': SettingSaid(
    'Delete what is chosen',
    'The key that deletes the selection. Undoable, like everything else.',
  ),
  'keys.escape': SettingSaid(
    'Back out',
    'The key that closes an open menu, then drops a selection, then leaves what '
        'you are in — one rung at a time.',
  ),
  'keys.focusDown': SettingSaid(
    'Go to the window below',
    'The chord that moves your attention down one window.',
  ),
  'keys.focusLeft': SettingSaid(
    'Go to the window left',
    'The chord that moves your attention one window to the left.',
  ),
  'keys.focusRight': SettingSaid(
    'Go to the window right',
    'The chord that moves your attention one window to the right.',
  ),
  'keys.focusUp': SettingSaid(
    'Go to the window above',
    'The chord that moves your attention up one window.',
  ),
  'keys.lensDigits': SettingSaid(
    'Digits that pick a lens',
    'The digit keys that swap the focused window\'s lens, in the order the lens '
        'bar lists them.',
  ),
  'keys.moveDown': SettingSaid(
    'Move this window down',
    'The chord that moves the window itself down, rather than your attention.',
  ),
  'keys.moveLeft': SettingSaid(
    'Move this window left',
    'The chord that moves the window itself left, rather than your attention.',
  ),
  'keys.moveRight': SettingSaid(
    'Move this window right',
    'The chord that moves the window itself right, rather than your attention.',
  ),
  'keys.moveUp': SettingSaid(
    'Move this window up',
    'The chord that moves the window itself up, rather than your attention.',
  ),
  'keys.newView': SettingSaid('Open another view', 'The key that opens a new view window.'),
  'keys.panBack': SettingSaid(
    'Slide back in time',
    'The key that slides the view one step towards the past.',
  ),
  'keys.panForward': SettingSaid(
    'Slide forward in time',
    'The key that slides the view one step towards the future.',
  ),
  'keys.redo': SettingSaid('Redo', 'The chord that puts back what you just undid.'),
  'keys.save': SettingSaid('Write the document down', 'The chord that saves now.'),
  'keys.tabTile': SettingSaid(
    'Tab a window here',
    'The chord that opens the next window as a tab beside this one rather than '
        'splitting it.',
  ),
  'keys.undo': SettingSaid('Undo', 'The chord that walks one edit back.'),
  'keys.zoomIn': SettingSaid('Closer', 'The key that draws less time across the same room.'),
  'keys.zoomOut': SettingSaid('Wider', 'The key that draws more time across the same room.'),
  'keys.zoomTile': SettingSaid(
    'Fill the stage with this window',
    'The chord that swells the window you are in to the whole stage, and back.',
  ),

  // --- Lanes ----------------------------------------------------------------
  'lane.gap': SettingSaid(
    'Space between lanes',
    'The gap between one lane of marks and the next, in pixels.',
    low: '0',
    high: '20',
  ),
  'lane.minWidth': SettingSaid(
    'Narrowest a lane may be',
    'Below this a lens stops adding lanes and stacks instead, in pixels.',
    low: '4',
    high: '80',
  ),

  // --- The Lines lens -------------------------------------------------------
  'lines.apexFirst': SettingSaid(
    'Height of the first arc',
    'How high the first arc rises off its line, in pixels.',
    low: '10',
    high: '300',
  ),
  'lines.apexStep': SettingSaid(
    'Rise added per arc',
    'How much higher each further arc from the same point rises, in pixels.',
    low: '0',
    high: '200',
  ),
  'lines.axisTicks': SettingSaid(
    'Ticks along a line',
    'How many marks are stepped along a timeline\'s own axis.',
    low: '2',
    high: '40',
  ),
  'lines.clusterPixels': SettingSaid(
    'How close counts as one dot',
    'Points nearer than this on screen are drawn as one, in pixels.',
    low: '0',
    high: '80',
  ),
  'lines.companionStroke': SettingSaid(
    'Thickness of a companion line',
    'How thick a line other than the one in charge is drawn, in pixels.',
    low: '0',
    high: '12',
  ),
  'lines.companions': SettingSaid(
    'Companion lines drawn',
    'How many other timelines are drawn beside the one in charge.',
    low: '0',
    high: '40',
  ),
  'lines.days': SettingSaid(
    'Days across the lens',
    'How much time the Lines lens holds at once, in days.',
    low: '1',
    high: '3650',
  ),
  'lines.minDays': SettingSaid(
    'Closest the lens winds in',
    'The least time the Lines lens will hold, in days. The window number is the '
        'zoom, so this is how far in you can go — a fraction of a day is a few '
        'hours across the surface.',
    low: '1/100',
    high: '7',
  ),
  'lines.dotRadius': SettingSaid(
    'Size of a point',
    'How large a point on a line is drawn, in pixels.',
    low: '1',
    high: '20',
  ),
  'lines.fanSpread': SettingSaid(
    'Spread of a fan',
    'How far apart several staples leaving one point are fanned, in pixels.',
    low: '0',
    high: '90',
  ),
  'lines.fanStep': SettingSaid(
    'Step between fanned staples',
    'How much further each staple in a fan is pushed, in pixels.',
    low: '0',
    high: '60',
  ),
  'lines.padX': SettingSaid(
    'Room at the ends',
    'The blank room left at each end of a line, in pixels.',
    low: '0',
    high: '400',
  ),
  'lines.padY': SettingSaid(
    'Room above and below',
    'The blank room left above and below the lines, in pixels.',
    low: '0',
    high: '300',
  ),
  'lines.primeStroke': SettingSaid(
    'Thickness of the line in charge',
    'How thick the timeline leading the view is drawn, in pixels.',
    low: '0',
    high: '16',
  ),
  'lines.sharedDotRadius': SettingSaid(
    'Size of a shared point',
    'How large a point that more than one line meets at is drawn, in pixels.',
    low: '1',
    high: '24',
  ),
  'lines.stapleDashOff': SettingSaid(
    'Gap in a staple\'s dash',
    'The blank part of the dashed line drawn for a staple, in pixels.',
    low: '0',
    high: '20',
  ),
  'lines.stapleDashOn': SettingSaid(
    'Mark in a staple\'s dash',
    'The drawn part of the dashed line drawn for a staple, in pixels.',
    low: '0',
    high: '20',
  ),
  'lines.tickHeight': SettingSaid(
    'Height of a tick',
    'How far a tick stands off its line, in pixels.',
    low: '0',
    high: '40',
  ),
  'lines.topology': SettingSaid(
    'Draw the shape, not the clock',
    'On, the lines are laid out by how they connect rather than by when things '
        'happen — the warp reading.',
  ),
  'lines.unitTicks': SettingSaid(
    'Ticks per unit',
    'How many small marks are stepped inside one unit of a line.',
    low: '1',
    high: '60',
  ),

  // --- The marks themselves -------------------------------------------------
  'mark.dashOff': SettingSaid(
    'Gap in a dashed mark',
    'The blank part of a dashed mark, in pixels.',
    low: '0',
    high: '20',
  ),
  'mark.dashOn': SettingSaid(
    'Stroke in a dashed mark',
    'The drawn part of a dashed mark, in pixels.',
    low: '0',
    high: '20',
  ),
  'mark.doneOpacity': SettingSaid(
    'How solid a finished thing is',
    'Something already done is drawn this solid — present, and plainly behind '
        'you.',
    low: '0',
    high: '1',
  ),
  'mark.dotOff': SettingSaid(
    'Gap in a dotted mark',
    'The blank part of a dotted mark, in pixels.',
    low: '0',
    high: '20',
  ),
  'mark.dotOn': SettingSaid(
    'Dot in a dotted mark',
    'The drawn part of a dotted mark, in pixels.',
    low: '0',
    high: '20',
  ),
  'mark.overflowScale': SettingSaid(
    'Size of the overflow count',
    'How large the "and this many more" number is drawn against ordinary text.',
    low: '0.4',
    high: '2',
  ),
  'mark.pip': SettingSaid(
    'Size of a pip',
    'The dot standing for something with nothing to fill, in pixels.',
    low: '1',
    high: '20',
  ),
  'mark.sparseOpacity': SettingSaid(
    'How solid a faint mark is',
    'The lightest a mark is drawn before it stops being drawn at all.',
    low: '0',
    high: '1',
  ),
  'mark.stroke': SettingSaid(
    'Thickness of a mark',
    'How thick an ordinary mark\'s line is, in pixels.',
    low: '0',
    high: '8',
  ),
  'mark.strokeStrong': SettingSaid(
    'Thickness of a strong mark',
    'How thick a mark reading as important or a landmark is drawn, in pixels.',
    low: '0',
    high: '12',
  ),

  // --- The minimap ----------------------------------------------------------
  'minimap.amplitude': SettingSaid(
    'How high the wave rises',
    'The tallest the wave gets, as a share of the minimap\'s height.',
    low: '0',
    high: '1',
  ),
  'minimap.anchorHigh': SettingSaid(
    'Top of the counted band',
    'Where a counted mote may ride at its highest, as a share of the height.',
    low: '0',
    high: '1',
  ),
  'minimap.anchorLow': SettingSaid(
    'Bottom of the counted band',
    'Where a counted mote may ride at its lowest, as a share of the height.',
    low: '0',
    high: '1',
  ),
  'minimap.axisWidth': SettingSaid(
    'Thickness of the baseline',
    'How thick the line the wave rides on is drawn, in pixels.',
    low: '0',
    high: '6',
  ),
  'minimap.bandHigh': SettingSaid(
    'Top of the wave\'s band',
    'The highest the wave\'s soft band reaches, as a share of the height.',
    low: '0',
    high: '1',
  ),
  'minimap.bandLow': SettingSaid(
    'Bottom of the wave\'s band',
    'The lowest the wave\'s soft band reaches, as a share of the height.',
    low: '0',
    high: '1',
  ),
  'minimap.bandOpacity': SettingSaid(
    'Solidity of the band',
    'How solid the soft band around the wave is, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'minimap.baselineOpacity': SettingSaid(
    'Solidity of the baseline',
    'How solid the line the wave rides on is, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'minimap.bins': SettingSaid(
    'How finely the wave is sampled',
    'How many slices the whole span is counted in before the wave is drawn '
        'through them.',
    low: '32',
    high: '2048',
  ),
  'minimap.breathe': SettingSaid(
    'Depth of the breath',
    'How much the wave swells and settles as it sits, from still to obvious.',
    low: '0',
    high: '1',
  ),
  'minimap.breatheSeconds': SettingSaid(
    'Length of one breath',
    'How long the wave takes to swell and settle once, in seconds.',
    low: '4',
    high: '300',
  ),
  'minimap.breadthMax': SettingSaid(
    'Widest the minimap zooms out',
    'The most the range around the focus may be widened by the wheel, as a '
        'multiple of what it holds at rest.',
    low: '1',
    high: '512',
  ),
  'minimap.breadthMin': SettingSaid(
    'Closest the minimap zooms in',
    'The most the range around the focus may be narrowed by the wheel, as a '
        'multiple of what it holds at rest. It can never be zoomed into a '
        'single slice.',
    low: '0.01',
    high: '1',
  ),
  'minimap.busy': SettingSaid(
    'What makes a stretch look busy',
    'The formula the waveform reads busyness from, over four things each object '
        'carries: how much structure it holds beyond the staple that places it, '
        'how long it lasts in days, its composed display weight, and its own '
        'authored busy handling.',
  ),
  'minimap.busyQuantile': SettingSaid(
    'What counts as busy',
    'The share of slices a slice must be busier than to read as a crest.',
    low: '0',
    high: '1',
  ),
  'minimap.countable': SettingSaid(
    'When motes become countable',
    'At or under this many things in a slice, the minimap draws them as motes '
        'you can count instead of as dust.',
    low: '1',
    high: '40',
  ),
  'minimap.countSpan': SettingSaid(
    'Span one count covers',
    'How much time one counted mote stands for, in hours.',
    low: '1',
    high: '720',
  ),
  'minimap.zoomStep': SettingSaid(
    'How much one zoom step is',
    'One notch of ctrl and the wheel over the minimap multiplies how much time '
        'it shows around the focus by this.',
    low: '1.01',
    high: '4',
  ),
  'minimap.crestOpacity': SettingSaid(
    'Solidity of the crest',
    'How solid the wave\'s own leading edge is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'minimap.crestWidth': SettingSaid(
    'Thickness of the crest',
    'How thick the wave\'s leading edge is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'minimap.dustOpacity': SettingSaid(
    'Solidity of the dust',
    'How solid the grain riding the wave is, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'minimap.focusStroke': SettingSaid(
    'Thickness of the focus edge',
    'How thick the edge of the window you are looking through is drawn, in '
        'pixels.',
    low: '0',
    high: '8',
  ),
  'minimap.gain': SettingSaid(
    'How hard the wave answers',
    'How strongly a busy stretch lifts the wave. Low reads calm; high reads '
        'spiky.',
    low: '0',
    high: '2',
  ),
  'minimap.glint': SettingSaid(
    'Brightness of a glint',
    'How brightly a grain flashes as it passes, from none to obvious.',
    low: '0',
    high: '1',
  ),
  'minimap.glintScale': SettingSaid(
    'Size of a glint',
    'How much larger a glinting grain draws than a still one.',
    low: '1',
    high: '6',
  ),
  'minimap.grainPerPixel': SettingSaid(
    'Grain per pixel',
    'How much dust is laid down for each pixel of width.',
    low: '0',
    high: '2',
  ),
  'minimap.haze': SettingSaid(
    'Softness of the haze',
    'How far the glow around the wave spreads, in pixels.',
    low: '0',
    high: '20',
  ),
  'minimap.jitter': SettingSaid(
    'Unsteadiness of the grain',
    'How far a grain wanders from where the wave puts it, in pixels.',
    low: '0',
    high: '10',
  ),
  'minimap.labelInset': SettingSaid(
    'Gap around a label',
    'How far a label sits from the edge it is written against, in pixels.',
    low: '0',
    high: '20',
  ),
  'minimap.labelSize': SettingSaid(
    'Size of a minimap label',
    'The size the dates along the minimap are set in, in pixels.',
    low: '5',
    high: '20',
  ),
  'minimap.ladderBase': SettingSaid(
    'Step between rungs',
    'How much coarser each rung of the minimap\'s zoom ladder is than the one '
        'below it.',
    low: '1.1',
    high: '8',
  ),
  'minimap.ladderHalfStep': SettingSaid(
    'Where the half rungs fall',
    'Which rung of the ladder carries a halfway stop, so the useful spans are '
        'all reachable.',
    low: '1',
    high: '12',
  ),
  'minimap.ladderRungs': SettingSaid(
    'How many rungs',
    'How far the minimap\'s zoom ladder climbs.',
    low: '4',
    high: '60',
  ),
  'minimap.moteHalo': SettingSaid(
    'Glow around a mote',
    'How far the halo around a counted mote spreads, in pixels.',
    low: '0',
    high: '10',
  ),
  'minimap.moteMax': SettingSaid(
    'Most motes in a slice',
    'The most counted motes one slice will ever draw before it goes back to '
        'dust.',
    low: '1',
    high: '40',
  ),
  'minimap.moteSize': SettingSaid(
    'Size of a mote',
    'How large one countable thing is drawn, in pixels.',
    low: '1',
    high: '16',
  ),
  'minimap.moteSpread': SettingSaid(
    'Spread of the motes',
    'How far apart the motes in one slice are scattered, as a share of the '
        'slice.',
    low: '0',
    high: '1',
  ),
  'minimap.particleRadius': SettingSaid(
    'Size of a grain',
    'How large one grain of dust is drawn, in pixels.',
    low: '0.2',
    high: '4',
  ),
  'minimap.particles': SettingSaid(
    'How much dust there is',
    'How many grains ride the wave altogether.',
    low: '100',
    high: '40000',
  ),
  'minimap.rangeMultiple': SettingSaid(
    'How much wider than the view',
    'How many times the focused view\'s own span the minimap holds around it.',
    low: '1',
    high: '40',
  ),
  'minimap.rateSpread': SettingSaid(
    'Spread of grain speeds',
    'How differently one grain drifts from another, from all alike to all '
        'different.',
    low: '0',
    high: '2',
  ),
  'minimap.smooth': SettingSaid(
    'How much the wave is smoothed',
    'How many neighbouring slices are blended into each other before the wave '
        'is drawn.',
    low: '0',
    high: '40',
  ),
  'minimap.spread': SettingSaid(
    'How far one thing reaches',
    'How far along the minimap a single thing lifts the wave, in slices.',
    low: '0',
    high: '60',
  ),
  'minimap.tickWidth': SettingSaid(
    'Thickness of a tick',
    'How thick a date tick along the minimap is drawn, in pixels.',
    low: '0',
    high: '6',
  ),
  'minimap.twinkleDepth': SettingSaid(
    'Depth of the twinkle',
    'How far a grain dims and brightens as it drifts, from steady to blinking.',
    low: '0',
    high: '1',
  ),
  'minimap.twinkleSeconds': SettingSaid(
    'Length of one twinkle',
    'How long a grain takes to dim and brighten once, in seconds.',
    low: '2',
    high: '300',
  ),
  'minimap.twinkleSteps': SettingSaid(
    'Steps in a twinkle',
    'How many stops the twinkle passes through, so grains do not all pulse '
        'together.',
    low: '1',
    high: '20',
  ),
  'minimap.windowStroke': SettingSaid(
    'Thickness of the window edge',
    'How thick the box showing what the view holds is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'minimap.windowWash': SettingSaid(
    'Wash inside the window',
    'How strongly the stretch the view holds is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),

  // --- How the surface moves ------------------------------------------------
  'motion.duration': SettingSaid(
    'How long a change takes',
    'Every change of ground in the program arrives over this long, in '
        'milliseconds. Nothing snaps.',
    low: '0',
    high: '1000',
  ),

  // --- The calendar boundary -------------------------------------------------
  'ics.completedFrame': SettingSaid(
    'Frame a finished ToDo lands in',
    'A calendar file that says a to-do is completed has to say it about some '
        'frame of yours. This names that frame — the one place in the program '
        'where a frame is named by default, because the outside world already '
        'said something and it has to land somewhere. Nothing inside treats it '
        'as different from any other frame you make.',
  ),

  // --- The now line ---------------------------------------------------------
  'now.halo': SettingSaid(
    'Glow around now',
    'How far the halo around the now line spreads, in pixels.',
    low: '0',
    high: '12',
  ),
  'now.width': SettingSaid(
    'Thickness of the now line',
    'How thick the line standing at this instant is drawn, in pixels.',
    low: '0',
    high: '10',
  ),

  // --- The mouse and the wheel ----------------------------------------------
  // THE POINTER CHORDS (ISSUES 9.2, the keybindings page). Said in the same
  // words the keyboard chords are said in, because they belong on the same page
  // and answer the same question: what does this press mean?
  'perf.frameMillis': SettingSaid(
    'How long a frame may take',
    'What a surface already up must keep to for motion to read as butter, in '
        'milliseconds. Written as the rate it comes from, so it reads as sixty '
        'a second rather than as a rounded number.',
    low: '1000 / 240',
    high: '1000 / 15',
  ),
  'perf.paintMillis': SettingSaid(
    'How long a first paint may take',
    'What the FIRST paint of a heavy document may take before the wait is a '
        'thing a person notices, in milliseconds.',
    low: '50',
    high: '2000',
  ),
  'pointer.pan': SettingSaid(
    'Drag to move the view',
    'The press that slides the view under the pointer instead of touching what '
        'is on it. Write modifiers and a button joined by +, and | between ways '
        'of doing it: middle | shift+left is the middle button or shift and the '
        'left one.',
  ),
  'pointer.menu': SettingSaid(
    'Open the menu here',
    'The press that opens the menu this program draws, over whatever is under '
        'the pointer. A lens never shows the menu the platform would draw.',
  ),
  'pointer.create': SettingSaid(
    'Drag to make something',
    'The press that mints an object across the span it is dragged over, even '
        'where something already sits — which is how you make a thing through an '
        'existing block instead of moving the block out of the way.',
  ),
  'pointer.marquee': SettingSaid(
    'Drag a box around several',
    'The press that pulls a box and selects everything inside it. A drag term '
        'says the binding wants motion rather than a press held still.',
  ),
  'pointer.toggleSelect': SettingSaid(
    'Add one to the selection',
    'The press that adds what is under the pointer to what is already selected, '
        'or takes it back out, without letting go of the rest.',
  ),
  'pointer.zoomDirection': SettingSaid(
    'Which way the wheel zooms',
    'Positive is wheel-up-zooms-in, the way every map and browser reads. Write '
        'a negative number to have it the other way round.',
    low: '-1',
    high: '1',
  ),
  'pointer.doubleClickMillis': SettingSaid(
    'How quick a double click is',
    'Two clicks closer together than this are one double click, in '
        'milliseconds.',
    low: '100',
    high: '800',
  ),
  'pointer.dropInto': SettingSaid(
    'Drop inside a container',
    'Which modifier, held while a window is dragged, drops it INTO the '
        'container under the pointer rather than beside it on the stage. A '
        'plain drag always targets the stage; this one joins the inner tree, '
        'and the drop preview outlines which is about to happen.',
  ),
  'pointer.dragThreshold': SettingSaid(
    'How far before it is a drag',
    'The pointer must travel this far before a press becomes a drag, in pixels '
        '— so a click with a shaky hand is still a click.',
    low: '0',
    high: '30',
  ),
  'pointer.ghostCorner': SettingSaid(
    'Rounding of the drag ghost',
    'How rounded the outline you drag out is, in pixels.',
    low: '0',
    high: '16',
  ),
  'pointer.ghostLabelGap': SettingSaid(
    'Gap under the ghost label',
    'How far the words beside the drag ghost sit from it, in pixels.',
    low: '0',
    high: '24',
  ),
  'pointer.ghostLabelPad': SettingSaid(
    'Padding of the ghost label',
    'The room around the words beside the drag ghost, in pixels.',
    low: '0',
    high: '16',
  ),
  'pointer.ghostLabelSize': SettingSaid(
    'Size of the ghost label',
    'The size the words beside the drag ghost are set in, in pixels.',
    low: '6',
    high: '24',
  ),
  'pointer.ghostMinimum': SettingSaid(
    'Smallest the ghost gets',
    'The drag outline is never drawn smaller than this, in pixels, so a tiny '
        'drag is still visible.',
    low: '0',
    high: '40',
  ),
  'pointer.ghostOpacity': SettingSaid(
    'Solidity of the drag ghost',
    'How solid the outline you drag out is, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'pointer.ghostStroke': SettingSaid(
    'Thickness of the drag ghost',
    'How thick the outline you drag out is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'pointer.minimapGrab': SettingSaid(
    'How hard the minimap pulls',
    'How far the view slides for one notch of the wheel over the minimap.',
    low: '0',
    high: '8',
  ),
  'pointer.panStepFraction': SettingSaid(
    'How far one nudge slides',
    'One press of a pan key slides the view this share of what it holds.',
    low: '0',
    high: '1',
  ),
  'pointer.refusalPad': SettingSaid(
    'Padding of a refusal',
    'The room around a refusal spoken at the pointer, in pixels.',
    low: '0',
    high: '40',
  ),
  'pointer.wheelNotch': SettingSaid(
    'How much wheel is one notch',
    'How far the wheel must turn to count as one step, so a fine wheel and a '
        'clicky one both step once.',
    low: '10',
    high: '400',
  ),
  'pointer.zoomStep': SettingSaid(
    'How much one zoom step is',
    'One notch of zoom multiplies what the view holds by this. Above one is a '
        'wider view.',
    low: '1.01',
    high: '4',
  ),

  // --- The Radial lens ------------------------------------------------------
  'radial.arcWidth': SettingSaid(
    'Thickness of an arc',
    'How thick the arc drawn for a thing is, in pixels.',
    low: '1',
    high: '40',
  ),
  'radial.bandSpacingMax': SettingSaid(
    'Widest a ring band gets',
    'A band of the dial never grows wider than this, in pixels.',
    low: '4',
    high: '200',
  ),
  'radial.cycleDays': SettingSaid(
    'Days in one turn',
    'How much time one full turn of the dial covers, in days.',
    low: '0.04',
    high: '400',
  ),
  'radial.divisions': SettingSaid(
    'Divisions drawn',
    'How many spokes the dial is cut into. Zero lets the calendar\'s own '
        'declaration decide.',
    low: '0',
    high: '64',
  ),
  'radial.divisionsMax': SettingSaid(
    'Most divisions allowed',
    'However fine the calendar\'s declaration is, the dial draws no more spokes '
        'than this.',
    low: '4',
    high: '256',
  ),
  'radial.hourCycleDays': SettingSaid(
    'When the dial reads hours',
    'Under this many days in a turn, the dial labels hours, in days.',
    low: '0.1',
    high: '60',
  ),
  'radial.innerRadius': SettingSaid(
    'Inner edge of the dial',
    'How far from the middle the dial starts, in pixels.',
    low: '0',
    high: '400',
  ),
  'radial.inward': SettingSaid(
    'Turns drawn inward',
    'How many turns before the one you are on are still drawn.',
    low: '0',
    high: '20',
  ),
  'radial.labelGapX': SettingSaid(
    'How far labels stand apart, across',
    'Two labels nearer than this sideways are thinned to one, in pixels.',
    low: '0',
    high: '400',
  ),
  'radial.labelGapY': SettingSaid(
    'How far labels stand apart, down',
    'Two labels nearer than this vertically are thinned to one, in pixels.',
    low: '0',
    high: '100',
  ),
  'radial.labelHalo': SettingSaid(
    'Halo behind a label',
    'How far the ground behind a label is cleared so it reads over the arcs, in '
        'pixels.',
    low: '0',
    high: '12',
  ),
  'radial.labels': SettingSaid('Write the labels', 'Off, the dial draws its arcs and no words.'),
  'radial.majorEvery': SettingSaid(
    'Every how many spokes is major',
    'Which spokes are drawn strong. Zero lets the two rules below decide.',
    low: '0',
    high: '32',
  ),
  'radial.majorQuarter': SettingSaid(
    'Major spoke per quarter turn',
    'Which spoke is drawn strong when the dial reads in quarters.',
    low: '1',
    high: '32',
  ),
  'radial.majorWeek': SettingSaid(
    'Major spoke per week',
    'Which spoke is drawn strong when the dial reads in weeks.',
    low: '1',
    high: '32',
  ),
  'radial.monthCycleMax': SettingSaid(
    'When the dial reads months',
    'Past this many days in a turn, the dial labels months, in days.',
    low: '1',
    high: '400',
  ),
  'radial.noonTick': SettingSaid(
    'Thickness of the midday tick',
    'How thick the mark at the middle of the day is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'radial.outerRadius': SettingSaid(
    'Outer edge of the dial',
    'How far from the middle the dial reaches, in pixels.',
    low: '20',
    high: '1200',
  ),
  'radial.outward': SettingSaid(
    'Turns drawn outward',
    'How many turns past the one you are on are still drawn.',
    low: '0',
    high: '20',
  ),
  'radial.ribbonWidth': SettingSaid(
    'Width of a turn\'s ribbon',
    'How wide one turn\'s band of arcs runs, in pixels.',
    low: '2',
    high: '120',
  ),
  'radial.samplesPerTurn': SettingSaid(
    'Smoothness of a turn',
    'How many points one turn is drawn through. Higher is rounder and slower.',
    low: '12',
    high: '720',
  ),
  'radial.tickMajor': SettingSaid(
    'Thickness of a major tick',
    'How thick a strong spoke is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'radial.tickPlain': SettingSaid(
    'Thickness of a plain tick',
    'How thick an ordinary spoke is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'radial.tickStrong': SettingSaid(
    'Thickness of a strong tick',
    'How thick the strongest spoke is drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'radial.weekCycleDays': SettingSaid(
    'When the dial reads weeks',
    'Under this many days in a turn, the dial labels weeks, in days.',
    low: '1',
    high: '200',
  ),

  // --- Rulers ---------------------------------------------------------------
  'rule.preference': SettingSaid(
    'How hard a lens holds its preferred spacing',
    'How far past its own target spacing a lens will stretch its preferred '
        'ruler pair before it yields to the ladder. At one it holds no opinion '
        'and geometry decides everything.',
    low: '1',
    high: '12',
  ),
  'rule.extension': SettingSaid(
    'How far a ruler runs past',
    'How far a ruler line carries beyond the thing it measures, in pixels.',
    low: '0',
    high: '120',
  ),
  'rule.labelSpacing': SettingSaid(
    'Space a ruler label needs',
    'Two ruler labels closer than this are thinned to one, in pixels.',
    low: '4',
    high: '200',
  ),
  'rule.major': SettingSaid(
    'Thickness of a major line',
    'How thick the ruler\'s strong lines are drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'rule.majorOpacity': SettingSaid(
    'Solidity of a major line',
    'How solid the ruler\'s strong lines are, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'rule.majorSpacing': SettingSaid(
    'Room a major line needs',
    'The least room between two strong ruler lines before the ruler steps to a '
        'coarser rung, in pixels.',
    low: '4',
    high: '300',
  ),
  'rule.minor': SettingSaid(
    'Thickness of a minor line',
    'How thick the ruler\'s faint lines are drawn, in pixels.',
    low: '0',
    high: '8',
  ),
  'rule.minorOpacity': SettingSaid(
    'Solidity of a minor line',
    'How solid the ruler\'s faint lines are, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'rule.minorSpacing': SettingSaid(
    'Room a minor line needs',
    'The least room between two faint ruler lines before they are dropped, in '
        'pixels.',
    low: '2',
    high: '200',
  ),

  // --- What selection looks like --------------------------------------------
  'selection.inner': SettingSaid(
    'Gap inside the ring',
    'How far the selection ring stands off the thing it rings, in pixels.',
    low: '0',
    high: '12',
  ),
  'selection.ring': SettingSaid(
    'Thickness of the ring',
    'How thick the ring around the chosen thing is drawn, in pixels.',
    low: '0',
    high: '12',
  ),
  'selection.ringOpacity': SettingSaid(
    'Solidity of the ring',
    'How solid the selection ring is, from clear to solid.',
    low: '0',
    high: '1',
  ),

  // --- These settings cards -------------------------------------------------
  'settings.general': SettingSaid(
    'The settings on the front card',
    'Which settings the main card puts in front of you, written as key names '
        'with spaces between them. Everything else is a click away on the card '
        'for the surface it governs.',
  ),

  // --- The Spiral lens ------------------------------------------------------
  'spiral.innerRadius': SettingSaid(
    'Where the spiral starts',
    'How far from the middle the first turn of the spiral begins, in pixels.',
    low: '0',
    high: '400',
  ),
  'spiral.samplesPerTurn': SettingSaid(
    'Smoothness of a turn',
    'How many points one turn of the spiral is drawn through.',
    low: '12',
    high: '720',
  ),
  'spiral.spacingMax': SettingSaid(
    'Widest the turns get',
    'Two turns of the spiral never stand further apart than this, in pixels.',
    low: '4',
    high: '300',
  ),

  // --- The stage and its windows --------------------------------------------
  'stage.barShare': SettingSaid(
    'Share of the stage a bar takes',
    'How much of the stage\'s height a bar starts with, as a fraction. Its own '
        'contents raise it from there.',
    low: '0',
    high: '1',
  ),
  'stage.barWidth': SettingSaid(
    'Width of a side bar',
    'How wide a bar standing on its side runs, in pixels.',
    low: '80',
    high: '600',
  ),
  'stage.divider': SettingSaid(
    'Thickness of a drag bar',
    'How thick the bar between two windows is drawn, in pixels.',
    low: '1',
    high: '20',
  ),
  'stage.dividerHit': SettingSaid(
    'How near counts as grabbing it',
    'How close the pointer must come to a drag bar to take hold of it, in '
        'pixels.',
    low: '2',
    high: '40',
  ),
  'stage.dropWash': SettingSaid(
    'Wash where a window would land',
    'How strongly the place a dragged window would go is tinted, from clear to '
        'solid.',
    low: '0',
    high: '1',
  ),
  'stage.edgeZone': SettingSaid(
    'How near an edge is an edge',
    'How much of a window counts as its edge when you drop something on it, as '
        'a fraction — inside that, the drop tabs instead of splitting.',
    low: '0',
    high: '0.5',
  ),
  'stage.grip': SettingSaid(
    'Size of the drag handle',
    'How wide a target the hover handle on a window\'s edge gives you — the '
        'three dots you pick a window up by, in pixels. A single window wears no '
        'resting name bar, so this is the whole affordance.',
    low: '4',
    high: '40',
  ),
  'stage.stripStays': SettingSaid(
    'Keep the tab strip on a single tab',
    'Whether a stack of tabs keeps its strip when it thins down to one tab. Off '
        'ships, because a window wears no resting chrome; on keeps the tab and '
        'its close mark standing where the hand last found them.',
  ),
  'stage.handleBand': SettingSaid(
    'Where the pointer finds the handle',
    'How wide the band down the leading edge of a window is, in pixels — bring '
        'the '
        'pointer inside it and the drag handle appears. A single window wears no '
        'resting bar, so this band is where its verbs live.',
    low: '8',
    high: '120',
  ),
  'stage.handleInset': SettingSaid(
    'How far in the handle sits',
    'How far from a window\'s edge its drag handle stands, in pixels.',
    low: '0',
    high: '30',
  ),
  'stage.mark': SettingSaid(
    'Size of a window mark',
    'How large the little marks on a window\'s chrome are, in pixels.',
    low: '6',
    high: '48',
  ),
  'stage.maxTabs': SettingSaid(
    'Tabs before they stack',
    'Past this many tabs on one window, the run splits into a stack rather than '
        'shaving every tab.',
    low: '2',
    high: '20',
  ),
  'stage.minimapWidth': SettingSaid(
    'Share of the row the minimap takes',
    'How much of its row the minimap starts with, as a fraction.',
    low: '0',
    high: '1',
  ),
  'stage.nudge': SettingSaid(
    'How far a keyed nudge moves',
    'One keyboard nudge of a drag bar moves it this share of the stage.',
    low: '0',
    high: '1',
  ),
  'stage.placement': SettingSaid(
    'Where a new window lands',
    'The whole rule list, authored: which neighbour a new window goes to, and '
        'whether it tabs into that neighbour or splits it — per kind of window. '
        'Shipped to tab into the right-hand neighbour where there is one, and '
        'to split only where there is not.',
  ),
  'stage.seamWash': SettingSaid(
    'Wash over a shown drag bar',
    'How strongly a drag bar is tinted while you are holding the key that shows '
        'them, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'stage.radius': SettingSaid(
    'Rounding of a window',
    'How rounded a window\'s corner is, in pixels.',
    low: '0',
    high: '20',
  ),
  'stage.snapTo': SettingSaid(
    'What a drag bar snaps to',
    'The word naming what a dragged divider settles on — ratio settles on clean '
        'fractions of the room.',
  ),
  'stage.splitRatio': SettingSaid(
    'How a split divides',
    'When a window splits, this share goes to the first half.',
    low: '0',
    high: '1',
  ),
  'stage.strip': SettingSaid(
    'Height of a tab strip',
    'How tall the run of tabs across a window stands, in pixels.',
    low: '10',
    high: '80',
  ),
  'stage.zoomKeepsBars': SettingSaid(
    'Keep the bars when a window swells',
    'On, swelling a window to fill the stage leaves the bars standing; off, it '
        'takes the whole screen.',
  ),

  // --- The Strategic lens ---------------------------------------------------
  'strategic.months': SettingSaid(
    'Months across the lens',
    'How much time the Strategic lens holds at once, in months.',
    low: '1',
    high: '60',
  ),

  // --- The Tactical lens ----------------------------------------------------
  'tactical.columns': SettingSaid(
    'Columns across the lens',
    'How many days stand side by side on the Tactical lens.',
    low: '1',
    high: '31',
  ),
  'tactical.rows': SettingSaid(
    'Rows down the lens',
    'How many weeks stand one above another on the Tactical lens.',
    low: '1',
    high: '20',
  ),

  // --- The palette ----------------------------------------------------------
  'theme.name': SettingSaid(
    'Which palette is in force',
    'The name of the palette the surface is drawn in. The palette card is where '
        'one is written, applied and saved.',
  ),

  // --- The to-do lenses -----------------------------------------------------
  'todo.box': SettingSaid(
    'Size of the tick box',
    'How large the box you tick a to-do off in is drawn, in pixels.',
    low: '6',
    high: '40',
  ),
  'todo.captureHeight': SettingSaid(
    'Height of the capture line',
    'How tall the line you type a new to-do straight into stands, in pixels.',
    low: '16',
    high: '80',
  ),
  'todo.chooserRows': SettingSaid(
    'Rows in the column chooser',
    'How many frames the board lists at once when you stand a column or switch '
        'one. The list is a window over a find, never the whole document, so this '
        'is how much of the find you see before typing narrows it.',
    low: '3',
    high: '40',
  ),
  'todo.columnWidth': SettingSaid(
    'Width of a board column',
    'How wide one column of the board runs, in pixels.',
    low: '100',
    high: '600',
  ),
  'todo.gap': SettingSaid(
    'Space between to-do rows',
    'The gap between one to-do and the next, in pixels.',
    low: '0',
    high: '20',
  ),
  'todo.metaSize': SettingSaid(
    'Size of a to-do\'s small print',
    'The size the date and frame beside a to-do are set in, in pixels.',
    low: '5',
    high: '20',
  ),
  'todo.pad': SettingSaid(
    'Padding around a to-do',
    'The room between a to-do row\'s edge and its words, in pixels.',
    low: '0',
    high: '20',
  ),
  'todo.rowFootprint': SettingSaid(
    'Room one to-do takes',
    'How much height one to-do is budgeted, in pixels, when the list works out '
        'how many fit.',
    low: '10',
    high: '80',
  ),
  'todo.rowHeight': SettingSaid(
    'Height of a to-do row',
    'How tall one to-do row stands, in pixels.',
    low: '10',
    high: '80',
  ),
  'todo.sectionSize': SettingSaid(
    'Size of a section heading',
    'The size the headings dividing the list are set in, in pixels.',
    low: '6',
    high: '24',
  ),
  'todo.spanDays': SettingSaid(
    'Days the list looks ahead',
    'How far forward the to-do list gathers from, in days.',
    low: '1',
    high: '400',
  ),
  'todo.sparseOpacity': SettingSaid(
    'How solid a faint to-do is',
    'The lightest a distant to-do is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'todo.titleSize': SettingSaid(
    'Size of a to-do\'s name',
    'The size a to-do\'s own words are set in, in pixels.',
    low: '6',
    high: '28',
  ),

  // --- The Tree lens --------------------------------------------------------
  'tree.edgeLength': SettingSaid(
    'How long a staple wants to be',
    'The distance the layout pulls two stapled things toward, in pixels. Larger '
        'spreads a neighbourhood out; smaller draws it tight.',
    low: '30',
    high: '600',
  ),
  'tree.edgeWidth': SettingSaid(
    'Thickness of a connection',
    'How thick the line between two nodes is drawn, in pixels.',
    low: '0',
    high: '10',
  ),
  'tree.settleCool': SettingSaid(
    'How fast the layout cools',
    'How much of its movement each settling pass keeps. Near one settles slowly '
        'and evenly; lower stops sooner and rougher.',
    low: '0.5',
    high: '0.999',
  ),
  'tree.settleSteps': SettingSaid(
    'Passes the layout may settle in',
    'How many passes the layout is allowed before it stands still, however '
        'unsettled it still is. More passes is a calmer picture and more work.',
    low: '20',
    high: '2000',
  ),
  'tree.halfDistance': SettingSaid(
    'How fast far things fade',
    'Every this many hops away, a node fades by half. Small numbers make the '
        'tree read as a neighbourhood; large ones flatten it.',
    low: '0.5',
    high: '20',
  ),
  'tree.hitPad': SettingSaid(
    'How near counts as hitting a node',
    'How far from a node the pointer may be and still take hold of it, in '
        'pixels.',
    low: '0',
    high: '40',
  ),
  'tree.labelGap': SettingSaid(
    'Gap under a node\'s name',
    'How far a node\'s name sits below it, in pixels.',
    low: '0',
    high: '60',
  ),
  'tree.labelFloor': SettingSaid(
    'When a label is dropped',
    'A node name is drawn while the node itself reads at least this strongly. '
        'Far labels drop first, and what is dropped is reported as a count.',
    low: '0',
    high: '1',
  ),
  'tree.labelPad': SettingSaid(
    'Room a label claims',
    'A measured label box is padded by this before it is checked against the '
        'labels already placed, in pixels.',
    low: '0',
    high: '20',
  ),
  'tree.nodeSize': SettingSaid(
    'Size of a node',
    'How large one node is drawn, in pixels.',
    low: '2',
    high: '60',
  ),
  'tree.reach': SettingSaid(
    'How far the tree walks',
    'How many hops from what you are looking at the tree draws.',
    low: '1',
    high: '10',
  ),
  'tree.ringSpacing': SettingSaid(
    'How much a crowded ring pushes out',
    'The narrowest two ring-mates may sit, as a share of one ring step: a ring '
        'earns its radius from what it holds. Zero is the old fixed spacing.',
    low: '0',
    high: '3',
  ),
  'tree.ringStep': SettingSaid(
    'Room between rings',
    'How much further out each ring of the tree sits, in pixels.',
    low: '10',
    high: '600',
  ),
  'tree.wheelPan': SettingSaid(
    'How far a wheel notch pans',
    'One notch of the wheel over the tree slides it this many pixels.',
    low: '10',
    high: '400',
  ),
  'tree.zoomMax': SettingSaid(
    'Closest the tree goes',
    'The most the ring spacing may be scaled up by ctrl and the wheel.',
    low: '1',
    high: '40',
  ),
  'tree.zoomMin': SettingSaid(
    'Widest the tree goes',
    'The most the ring spacing may be scaled down by ctrl and the wheel.',
    low: '0.01',
    high: '1',
  ),
  'tree.ringTurn': SettingSaid(
    'How much each ring is turned',
    'How far each ring is rotated against the one inside it, in turns, so '
        'branches do not line up behind each other.',
    low: '0',
    high: '1',
  ),

  // --- The Wall lens --------------------------------------------------------
  'wall.detail': SettingSaid(
    'Draw the detail',
    'On, the wall calendar draws what is in each day; off, it draws the shape '
        'of the months alone.',
  ),
  'wall.firstWeekday': SettingSaid(
    'Which day the week starts on',
    'Counted from the first day the calendar itself declares, so a calendar '
        'with its own week is answered in its own terms.',
    low: '0',
    high: '6',
  ),
  'wall.months': SettingSaid(
    'Months across the lens',
    'How many months the wall calendar holds at once.',
    low: '1',
    high: '36',
  ),

  // --- Display weight -------------------------------------------------------
  'weight.halfDistanceDays': SettingSaid(
    'How fast distance thins things',
    'Every this many days away, an unresolved thing weighs half as much. This '
        'is apparent magnitude: near matters more.',
    low: '1',
    high: '365',
  ),

  // --- Zone fills -----------------------------------------------------------
  'zone.default': SettingSaid(
    'Fill a zone by default',
    'Whether a frame that says nothing about zone fill gets one. Nothing here '
        'encodes a right way; a frame that authors an answer wins.',
    low: '0',
    high: '1',
  ),
  'zone.edge': SettingSaid(
    'Strength of a zone\'s edge',
    'How strongly the boundary of a zone is drawn, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'zone.fill': SettingSaid(
    'Strength of a zone\'s fill',
    'How strongly the inside of a zone is tinted, from clear to solid.',
    low: '0',
    high: '1',
  ),
  'zone.radius': SettingSaid(
    'Rounding of a zone',
    'How rounded a zone\'s corners are, in pixels.',
    low: '0',
    high: '30',
  ),
  'zone.rule': SettingSaid(
    'Thickness of a zone\'s edge',
    'How thick the boundary of a zone is drawn, in pixels.',
    low: '0',
    high: '10',
  ),
};
