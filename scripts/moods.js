import { spotify } from "../src/spotify.js";
const PLAN = [
  { target: "695WgQfpVFAgrEHrvDMJD3", name: "Work",  from: ["28VvQQMQSbo7ojE1P46ODG", "2fiKcLkT0KK9VyRBJZx7cX"] },
  { target: "7C1tfLLh48URkLZ15sSzbs", name: "Drive", from: ["6h1B62CKvVIdqn8ec6tn8L"] },
  { target: "3hkBZxRDQRCrLAZFg93hES", name: "Hype",  from: ["6OBTYBLb7vYZMNYXGMBI7T", "793TXkHK06vnWCkynGIoNm", "5rDIzzGiIMB18rDkhqsLYu"] },
  { target: "4OicyLPbx4FFeXwdavGWAk", name: "Party", from: ["7eb2B6gb9RrTgoNUti0CUg", "1OcDRUhYWqe6EpW6kh0cfV"] },
  { target: "3Qu6zPttbgScuiLRwamemD", name: "עברית", from: ["1Ge4Zgw0UPUi361L4t0EVo"] },
];
for (const p of PLAN) {
  await spotify.updatePlaylist(p.target, { name: p.name, description: "" });
  const r = await spotify.mergePlaylists({ sourceIds: p.from, targetId: p.target, deleteSources: false });
  console.log(`${p.name.padEnd(6)} +${r.added} → ${(await spotify.getPlaylist(p.target)).tracks.length} tracks`);
}
