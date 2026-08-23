import { spotify, api } from "../src/spotify.js";
import { readFileSync } from "node:fs";
const lib = JSON.parse(readFileSync(process.argv[2], "utf8"));

const LIKE = [
 // Work
 "Khruangbin Maria También","Bonobo Kerala","Men I Trust Show Me How","Nujabes Aruarian Dance","Yussef Dayes Black Classical Music","Cigarettes After Sex Apocalypse","Parcels Overnight","Thundercat Them Changes","Tycho Awake","Jordan Rakei Mad World",
 // Drive
 "The War on Drugs Red Eyes","Fleetwood Mac The Chain","Tom Petty Runnin' Down a Dream","Creedence Clearwater Revival Fortunate Son","Creedence Clearwater Revival Have You Ever Seen the Rain","Fontaines D.C. Starburster","The Smile You Will Never Work in Television Again","Father John Misty Real Love Baby","Bruce Springsteen Dancing in the Dark","Spoon The Underdog","The Black Keys Lonely Boy","Led Zeppelin Ramble On","Supertramp The Logical Song","Dire Straits Tunnel of Love",
 // Hype
 "Vini Vici The Tribe","Astrix Deep Jungle Walk","Pendulum Witchcraft","Deftones My Own Summer","Sleep Token The Summoning","Turnstile BLACKOUT","Spiritbox Circle With Me","Bad Omens Just Pretend","The Prodigy Breathe","Ace Ventura Rebirth",
 // Party
 "Fred again.. Marea","Dom Dolla Saving Up","Peggy Gou It Goes Like Nanana","Central Cee Doja","Tyler The Creator EARFQUAKE","Apache 207 Roller","Luciano Beautiful Girl","Peer Tasi דרך השלום","Doechii Anxiety","Rosalía DESPECHÁ",
 // עברית
 "Yehuda Poliker פחות אבל כואב","Rona Kenan גשם כבד","Ester Rada Life Happens","Knesiyat Hasekhel דמעות של מלאכים","Tamir Grinberg אין לי ארץ אחרת","Nunu הו תעזוב","Asaf Avidan One Day Reckoning Song","Dudu Tassa Ya Mishtaq","Shalom Hanoch מחכים למשיח","Kaveret המגפיים של ברוך",
];
const PROGRAMMING_NEW = [
 "Tycho Awake","Bonobo Kerala","Khruangbin Maria También","Nujabes Aruarian Dance","Emancipator Soon It Will Be Cold Enough","Lane 8 Brightest Lights","Jon Hopkins Open Eye Signal","Ólafur Arnalds Near Light","Nils Frahm Says","Kiasmos Blurred","Boards of Canada Roygbiv","Four Tet Baby","Bonobo Cirrus","Tycho A Walk","RJD2 Ghostwriter","Com Truise Propagation","Carbon Based Lifeforms Abiogenesis","Tipper Reality Harshness Defender","Ott Owl Stretching Time","Shpongle Divine Moments of Truth","Stavroz The Finishing","Be Svendsen Mirror Mirror","Parra for Cuva Wicked Games","Lemon Jelly Nice Weather for Ducks","Röyksopp Eple","Air La Femme d'Argent","Zero 7 Destiny","Thievery Corporation Lebanese Blonde","Massive Attack Teardrop","Portishead Glory Box",
];
const SHISHI_ARTISTS = ["shlomo artzi","eviatar banai","ehud banai","jane bordeaux","beit habubot","dudu tassa","arik einstein","yehudit ravitz","rona kenan","eric berman","ivri lider","חנן בן ארי","ishay ribo","shalom hanoch","mashina","yoni rechter","meir ariel","berry sakharof","fortisakharof","hadag nahash","idan raichel","lola marsh","theangelcy","amir dadon","nathan goshen","yoni bloch","girafot","mofa haarnavot shel dr. kasper","ehud banai","shlomi shaban","alon eder","tuna","full trunk","osher cohen","eden hason","jasmin moallem","aviv geffen","kaveret","yehuda poliker","ester rada","nunu","asaf avidan","geva alon","tamir grinberg","avihu pinhasov rhythm club","elai botner","habiluim","teapacks"];
const SHISHI_NEW = [
 "Idan Raichel מבוקר עד ערב","Arik Einstein עוף גוזל","Shlomo Artzi תחת שמי ים התיכון","Ehud Banai עיר מקלט","Meir Ariel שיר כאב","Yehudit Ravitz בוא","Jane Bordeaux מה עכשיו","Beit Habubot בלון","Eviatar Banai יפה כלבנה","Ivri Lider זכיתי לאהוב","Hanan Ben Ari סופרסטאר","Ishay Ribo לשוב הביתה","Dudu Tassa ובלילות","Shalom Hanoch לילה","Berry Sakharof חלומות שמורים","Matti Caspi ברית עולם","Shlomi Shaban מכתבים ליטאיים","Rona Kenan כשאת עצובה","Lola Marsh Wishing Girl","Hadag Nahash שירת הסטיקר","Yonatan Razel קטונתי","Amir Dadon עד מתי","Eric Berman מה שנשאר","Alon Eder סלח לי","Yoni Bloch חגיגה","Tuna הולכת","Mashina רכבת לילה לקהיר","Kaveret פה קבור הכלב","Ehud Banai הזמן עובר","Avihu Pinhasov Rhythm Club בית שני",
];

async function find(q) { const r = await spotify.search(q, "track", 1); return r[0]; }
async function resolve(list, label) {
  const ids = [], miss = [];
  for (const q of list) { const t = await find(q); t ? ids.push(t.id) : miss.push(q); }
  console.log(`${label}: found ${ids.length}/${list.length}${miss.length ? "  missing: " + miss.join(" | ") : ""}`);
  return ids;
}
const have = new Set(lib.liked.map((t) => t.id));

// 1. Like the picks
const likeIds = (await resolve(LIKE, "likes")).filter((id) => !have.has(id));
await spotify.saveTracks(likeIds);
console.log(`liked ${likeIds.length} new songs`);

// 2. Programming: original 57 + new instrumentals
const origProg = lib.playlists["695WgQfpVFAgrEHrvDMJD3"].tracks.map((t) => t.id);
const prog = await spotify.createPlaylist({ name: "Programming", description: "Instrumental / downtempo for deep work" });
const progNew = await resolve(PROGRAMMING_NEW, "programming picks");
console.log("Programming:", await spotify.addTracks(prog.id, [...origProg, ...progNew]));

// 3. שישי: mellow Israeli from library + new
const pool = new Map(); for (const t of [...lib.liked, ...Object.values(lib.playlists).flatMap((p) => p.tracks)]) pool.set(t.id, t);
const fromLib = [...pool.values()].filter((t) => SHISHI_ARTISTS.includes(t.artists.split(", ")[0].toLowerCase())).map((t) => t.id);
const shishi = await spotify.createPlaylist({ name: "שישי", description: "שישי בצהריים · Friday noon" });
const shishiNew = await resolve(SHISHI_NEW, "שישי picks");
console.log("שישי:", await spotify.addTracks(shishi.id, [...fromLib, ...shishiNew]), "from library:", fromLib.length);
