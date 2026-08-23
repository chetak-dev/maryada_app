/// The blocking word lists that ship inside the child app, mirrored here so the
/// site admin can see everything that blocks — not just the words they added.
///
/// Keep in sync with `ContentFilter.kt` (STRONG_BY_CATEGORY / WEAK_BY_CATEGORY)
/// in the child app; these are for display only, the device uses its own copy.
library;

/// Unambiguous terms — one occurrence on a page blocks it.
const Map<String, List<String>> kBuiltinStrongKeywords = {
  'adult': [
    'pornhub', 'xvideos', 'xnxx', 'xhamster', 'redtube', 'youporn',
    'brazzers', 'onlyfans', 'hentai', 'camgirl', 'camsoda', 'chaturbate',
    'spankbang', 'redgifs', 'youjizz', 'tube8', 'motherless', 'tnaflix',
    'eporner', 'porntrex', 'fapello', 'nhentai', 'e-hentai', 'hqporner',
    'beeg', 'txxx', 'hclips', 'adultfriendfinder', 'stripchat',
    'bongacams', 'livejasmin', 'myfreecams', 'fansly', 'manyvids',
    'rule34', 'child porn',
    'spankwire', 'keezmovies', 'drtuber', 'sunporno', 'porn300',
    'porndig', 'thumbzilla', 'vporn', 'faphouse', 'javhd', 'javbus',
    'missav', 'hanime', 'hentaihaven', 'fakku', 'pornhd', '4tube',
    'empflix', 'xmoviesforyou', 'desixnxx', 'desipapa', 'cam4',
    'flirt4free', 'streamate', 'imlive', 'xhamsterlive', 'porhub',
    'pornky', 'okxxx', '3movs', 'sexvid', 'anysex',
  ],
  'gambling': [
    '1xbet', 'bet365', 'dafabet', 'parimatch', 'stake.com', 'betway',
    'melbet', '22bet', 'betwinner', 'mostbet', '4rabet', '10cric',
    'casumo', 'leovegas', 'ladbrokes', 'williamhill', 'pokerstars',
    'betfair', 'unibet', '888casino', 'rummycircle', 'pokerbaazi',
    'sattaking', 'price boost', 'bet slip', 'betslip', 'bet builder',
    'in-play betting', 'sportsbook', 'live betting',
    '1win', 'linebet', 'megapari', 'rajabets', 'fun88', '9winz',
    'betandreas', 'pin-up casino', 'crickex', 'baji live', 'babu88',
    'jeetwin', 'betvisa', 'lotus365', 'laser247', 'world777',
    'reddy anna', 'mahadev book', 'fairplay', 'betbhai', 'sky exchange',
    'skyexchange', 'diamond exchange', 'lords exchange',
    'tiger exchange', 'gullybet', 'indibet', 'betdaily', 'dpboss',
    'kalyan matka', 'winzo', 'junglee rummy', 'a23 rummy', 'rummy glee',
  ],
  'drugs': [
    'how to make meth', 'buy cocaine', 'buy heroin online', 'buy mdma',
    'buy lsd', 'buy fentanyl', 'buy ketamine', 'buy weed online',
    'order cocaine', 'buy cannabis online', 'buy meth online',
    'dark web drugs', 'buy shrooms online',
  ],
  'weapons': [
    'how to make a bomb', 'buy guns online', 'buy a gun online',
    'buy a ghost gun',
  ],
  'violence': [
    'how to commit suicide', 'ways to kill yourself', 'suicide methods',
    'how to hang yourself', 'painless suicide', 'how to kill myself',
  ],
};

/// Generic terms that also appear in safe contexts — several distinct hits on
/// the same page are needed before it is blocked.
const Map<String, List<String>> kBuiltinWeakKeywords = {
  'adult': [
    'porn', 'nsfw', 'xxx', 'sex video', 'sex videos', 'adult video',
    'porn video', 'nude photos', 'nude pics', 'nude girls',
    'naked girls', 'escort service', 'sex cam', 'camsex', 'live sex',
    'sex chat', 'webcam girls', 'adult webcam', 'milf', 'blowjob',
    'threesome', 'cumshot', 'hardcore porn', 'sex tube',
    'free porn', 'sex movies', 'porn site', 'adult movies', 'xxx video',
    'camgirls', 'escort', 'call girl', 'anal sex', 'gangbang',
    'creampie', 'deepthroat', 'handjob', 'fetish porn', 'sex stories',
    'adult chat', 'nude video', 'sexting', 'onlyfans leak', 'nude leak',
  ],
  'gambling': [
    'casino', 'online casino', 'poker', 'betting', 'roulette',
    'blackjack', 'jackpot', 'wager', 'slot machine', 'online lottery',
    'free spins', 'place a bet', 'betting odds', 'deposit bonus',
    'real money casino', 'teen patti', 'andar bahar', 'rummy',
    'satta matka', 'lottery ticket', 'cash out', 'accumulator',
    'match odds', 'free bet', 'betting tips', 'in-play',
    'cricket betting', 'ipl betting', 'online betting',
    'sports betting', 'betting site', 'betting app', 'casino games',
    'win real money', 'color prediction', 'colour prediction',
    'aviator game', 'crash game', 'real cash game', 'matka result',
    'spin and win', 'dragon tiger',
  ],
  'drugs': [
    'cocaine', 'heroin', 'marijuana', 'cannabis', 'lsd', 'mdma',
    'ecstasy', 'methamphetamine', 'buy drugs', 'buy weed',
    'magic mushrooms', 'fentanyl', 'ketamine', 'hashish', 'opioids',
    'thc', 'weed for sale', 'cannabis oil', 'buy hashish',
    'crystal meth',
  ],
  'violence': [
    'gore', 'beheading', 'graphic violence', 'extremely graphic',
    'murder video', 'execution video', 'torture video', 'snuff film',
    'self harm', 'self-harm', 'cutting myself', 'pro ana', 'thinspo',
    'gore video', 'death video', 'watch people die', 'beheading video',
  ],
  'weapons': [
    'buy firearm', 'buy ammunition', 'buy handgun', 'buy gun',
    'ghost gun', 'buy ammo', 'silencer for sale',
  ],
};

int builtinCount(String category) =>
    (kBuiltinStrongKeywords[category]?.length ?? 0) +
    (kBuiltinWeakKeywords[category]?.length ?? 0);
