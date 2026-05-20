// One-time conversion tool that produces explicit legacy evidence transcripts
// from the verbatim legacy core. The tool links directly against
// `cpp-legacy/legacy-core/` (the byte-identical port of
// `~/MCTS_legacy/backend/core/`) so the captured transcripts reflect the
// legacy's own search behavior. The output uses the Phase 2 wire format
// documented in `documents/engineering/transcript_format.md`; one .tr file
// per game (file name is sha256(payload)).
//
// Supported regeneration entrypoint (from project root):
//     docker compose run --rm mcts mcts build legacy-fixtures --output-dir /tmp/mcts-legacy-fixtures --seed 42 --games 10 --sims 10000
//
// Pinned report-card knobs per
// `DEVELOPMENT_PLAN/phase-7-cross-backend-verify-and-report-card.md`:
//     S_LP       = 42       (master seed)
//     G_LP       = 10       (games)
//     S_LP_SIMS  = 10000    (sims per move)
//     max_plies  = 10000    (legacy parity envelope)
//
// The output filenames are sha256(file_bytes).tr; the file structure is the
// one-game transcript (header + envelope + single GameTranscript) so the
// `mcts-integration` stanza can compare byte-for-byte. The transcripts are
// regenerated only when the upstream legacy at `~/MCTS_legacy/backend/core/`
// is upgraded; otherwise the directory is a frozen historical record.

#include "../legacy-core/board.h"
#include "../legacy-core/mcts.hpp"

#include <algorithm>
#include <array>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <random>
#include <string>
#include <tuple>
#include <vector>

namespace fs = std::filesystem;

namespace {

// Report-card knobs per phase-7. The official fixture set uses these
// exact values; the supported `mcts build legacy-fixtures` entrypoint
// passes them explicitly for quick smoke runs or the full fixture refresh
// (the long-form fixture is a frozen historical record that regenerates
// only when `~/MCTS_legacy` is upgraded).
constexpr uint64_t DEFAULT_SEED = 42;
constexpr uint32_t DEFAULT_GAMES = 10;
constexpr uint32_t DEFAULT_SIMS = 10000;
constexpr uint16_t LEGACY_MAX_PLIES = 10000;
constexpr int LEGACY_HARD_PLY_CAP = 10000;
constexpr uint64_t DEFAULT_C_PARAM_BITS = 0x3fe6666666666666ULL; // 0.7

uint64_t REPORT_CARD_SEED = DEFAULT_SEED;
uint32_t REPORT_CARD_GAMES = DEFAULT_GAMES;
uint32_t REPORT_CARD_SIMS = DEFAULT_SIMS;

// SplitMix64 used by `MCTS.Rng.Mix.mix` to derive a per-game sub-seed from
// (master_seed, game_index). Verbatim copy of the Haskell implementation.
uint64_t splitmix64_step(uint64_t state) {
    state += 0x9E3779B97F4A7C15ULL;
    uint64_t z = state;
    z = (z ^ (z >> 30)) * 0xBF58476D1CE4E5B9ULL;
    z = (z ^ (z >> 27)) * 0x94D049BB133111EBULL;
    return z ^ (z >> 31);
}

uint64_t mix_seed(uint64_t master, uint64_t game_index) {
    return splitmix64_step(master ^ game_index);
}

uint8_t parse_action_id(const std::string &action) {
    if (action.size() < 5) return 0;
    const bool pawn = action[0] == '*';
    const bool horizontal = action[0] == 'H';
    const bool vertical = action[0] == 'V';
    const size_t open = action.find('(');
    const size_t comma = action.find(',');
    const size_t close = action.find(')');
    if (open == std::string::npos || comma == std::string::npos || close == std::string::npos) {
        return 0;
    }
    const int x = std::stoi(action.substr(open + 1, comma - open - 1));
    const int y = std::stoi(action.substr(comma + 1, close - comma - 1));
    if (pawn) return static_cast<uint8_t>(y * 9 + x);
    if (horizontal) return static_cast<uint8_t>(81 + y * 8 + x);
    if (vertical) return static_cast<uint8_t>(145 + y * 8 + x);
    return 0;
}

// Flip an action id between the legacy's "current player at y=0" perspective
// and the Haskell absolute (Hero-at-y=0) enumeration. The transform mirrors
// `applyFlip` in `src/MCTS/Driver/CppLegacy.hs`.
uint8_t flip_action_id(uint8_t aid) {
    if (aid <= 80) return static_cast<uint8_t>(80 - aid);
    if (aid <= 144) return static_cast<uint8_t>(225 - aid);
    if (aid <= 208) return static_cast<uint8_t>(353 - aid);
    return aid;
}

struct MoveRecord {
    uint16_t move_index;
    uint8_t chosen;
    std::vector<std::pair<uint8_t, uint32_t>> visits;
};

struct GameTranscript {
    uint32_t game_id;
    std::vector<MoveRecord> moves;
    uint8_t winner; // 0=hero, 1=villain, 2=draw (legacy never produces draw)
};

GameTranscript play_one_game(uint64_t game_seed, uint32_t game_id) {
    auto root = std::make_shared<mcts::uct_node<corridors::board>>(corridors::board{});
    mcts::Rand rng(game_seed);

    GameTranscript transcript{game_id, {}, 2};
    int ply = 0;
    bool hero_to_move = true;
    while (ply < LEGACY_HARD_PLY_CAP) {
        if (root->get_state().is_terminal()) {
            // Legacy's hero/villain flip every move: track via ply parity.
            // hero_wins() on the *current* root means the side-to-move has
            // already won (since the win-check fires before flipping). In
            // legacy terms, the side-to-move at an EVEN ply (0,2,...) is
            // Haskell's Hero; at an ODD ply, Haskell's Villain.
            // is_terminal() returns true when either side has just landed
            // on their goal — that's the move that ended the game, played
            // by the previous mover. After the move, the board flipped,
            // so the previous mover is now the "villain" of the current
            // root.
            if (root->get_state().villain_wins()) {
                transcript.winner = hero_to_move ? 1 : 0;
            } else if (root->get_state().hero_wins()) {
                transcript.winner = hero_to_move ? 0 : 1;
            } else {
                transcript.winner = 2;
            }
            break;
        }

        rng.seed(game_seed ^ static_cast<uint64_t>(ply * 257 + 1));
        // eval_children=false to mirror the upstream legacy's exact
        // simulate call pattern. With S_LP_SIMS=10000 every child of
        // the root gets explored naturally over the iteration loop, so
        // `choose_best_action`'s winning-moves get_equity check has
        // valid `eval_Q` values for every terminal child.
        root->simulate(static_cast<size_t>(REPORT_CARD_SIMS), rng, 1.4,
                       true, false, false, false);

        auto sorted = root->get_sorted_actions(false);
        std::vector<std::tuple<uint8_t, uint32_t>> records;
        records.reserve(sorted.size());
        for (const auto &mv : sorted) {
            uint32_t visits = static_cast<uint32_t>(std::min<size_t>(
                std::get<0>(mv), std::numeric_limits<uint32_t>::max()));
            uint8_t raw_aid = parse_action_id(std::get<2>(mv));
            uint8_t aid = hero_to_move ? flip_action_id(raw_aid) : raw_aid;
            records.emplace_back(aid, visits);
        }
        std::sort(records.begin(), records.end(),
                  [](const auto &a, const auto &b) {
                      return std::get<0>(a) < std::get<0>(b);
                  });

        std::shared_ptr<mcts::uct_node<corridors::board>> next;
        std::string action_text;
        try {
            next = root->choose_best_action(rng, 0.0, true);
            action_text = next->get_state().get_action_text(false);
        } catch (const std::string &) {
            // Late-game `check_non_terminal_eval` race: pick the highest-visit
            // child via action text. Matches the C ABI shim's fallback.
            const std::tuple<size_t, double, std::string> *best = nullptr;
            for (const auto &mv : sorted) {
                if (!best || std::get<0>(mv) > std::get<0>(*best)) {
                    best = &mv;
                }
            }
            if (!best) throw;
            action_text = std::get<2>(*best);
            next = root->make_move(action_text, false);
        }
        uint8_t raw_chosen = parse_action_id(action_text);
        uint8_t chosen = hero_to_move ? flip_action_id(raw_chosen) : raw_chosen;

        MoveRecord rec;
        rec.move_index = static_cast<uint16_t>(ply);
        rec.chosen = chosen;
        for (const auto &r : records) {
            rec.visits.emplace_back(std::get<0>(r), std::get<1>(r));
        }
        transcript.moves.push_back(std::move(rec));

        // Preserve the legacy's tree continuity: the new root keeps
        // its accumulated visit counts and evaluations. This matches
        // how the upstream legacy plays self-play (no re-rooting).
        root = next;
        ++ply;
        hero_to_move = !hero_to_move;
    }
    return transcript;
}

void write_u8(std::vector<uint8_t> &out, uint8_t v) { out.push_back(v); }
void write_u16(std::vector<uint8_t> &out, uint16_t v) {
    out.push_back(v & 0xff); out.push_back((v >> 8) & 0xff);
}
void write_u32(std::vector<uint8_t> &out, uint32_t v) {
    for (int i = 0; i < 4; ++i) out.push_back((v >> (8 * i)) & 0xff);
}
void write_u64(std::vector<uint8_t> &out, uint64_t v) {
    for (int i = 0; i < 8; ++i) out.push_back((v >> (8 * i)) & 0xff);
}

void write_fixed_zero(std::vector<uint8_t> &out, size_t n) {
    for (size_t i = 0; i < n; ++i) out.push_back(0);
}
void write_length_prefixed_63(std::vector<uint8_t> &out, const std::string &s) {
    std::string clipped = s.substr(0, 63);
    write_u8(out, static_cast<uint8_t>(clipped.size()));
    for (char c : clipped) out.push_back(static_cast<uint8_t>(c));
    for (size_t i = clipped.size(); i < 63; ++i) out.push_back(0);
}

uint8_t arch_id() {
#if defined(__aarch64__)
    return 1; // arm64
#else
    return 0; // amd64
#endif
}
std::string arch_dir() { return arch_id() == 1 ? "arm64" : "amd64"; }

void encode_header(std::vector<uint8_t> &out, uint8_t backend_id) {
    write_u8(out, 0x4D); write_u8(out, 0x43); write_u8(out, 0x54); write_u8(out, 0x52);
    write_u16(out, 1); // version
    write_u8(out, backend_id);
    write_u8(out, 0); // threading: single
    write_u16(out, 1); // workers
    write_u8(out, 1); // rng source: cpp
    write_u8(out, arch_id());
    write_u64(out, DEFAULT_C_PARAM_BITS);
    write_u32(out, 0);
    write_u64(out, REPORT_CARD_SEED);
    write_u32(out, REPORT_CARD_SIMS);
    write_u32(out, REPORT_CARD_SIMS);
    write_u16(out, LEGACY_MAX_PLIES);
    write_u16(out, 1); // workload: selfplay
    write_u32(out, 48); // flags placeholder
}

void encode_envelope(std::vector<uint8_t> &out, uint8_t backend_id) {
    // Build payload, then prefix with version + length.
    std::vector<uint8_t> payload;
    write_u8(payload, backend_id);
    write_u8(payload, 1); // rng source cpp
    write_u8(payload, arch_id());
    write_u8(payload, 0); // reserved
    write_fixed_zero(payload, 32); // shared_rng_build_id
    write_fixed_zero(payload, 32); // cohort_config_hash
    write_fixed_zero(payload, 32); // engine_build_id
    write_fixed_zero(payload, 40); // git commit
    write_u8(payload, 0); // compiler id gcc
    write_length_prefixed_63(payload, "");
    write_u32(payload, 0); // fp flags
    write_length_prefixed_63(payload, "");
    write_u32(payload, 0); // cpu features
    write_u8(payload, 0); // fp env
    write_length_prefixed_63(payload, "cpp-legacy-fixture");

    write_u16(out, 1); // envelope version
    write_u32(out, static_cast<uint32_t>(2 + 4 + payload.size()));
    out.insert(out.end(), payload.begin(), payload.end());
}

void encode_record(std::vector<uint8_t> &out, const MoveRecord &rec) {
    write_u16(out, rec.move_index);
    write_u8(out, rec.chosen);
    auto visits = rec.visits;
    if (visits.size() > 254) visits.resize(254);
    write_u8(out, static_cast<uint8_t>(visits.size()));
    for (auto &p : visits) {
        write_u8(out, p.first);
        write_u32(out, p.second);
    }
}

void encode_game(std::vector<uint8_t> &out, const GameTranscript &g) {
    write_u32(out, g.game_id);
    for (const auto &m : g.moves) encode_record(out, m);
    write_u8(out, 0xFF);
    write_u8(out, g.winner);
    write_u16(out, static_cast<uint16_t>(g.moves.size()));
}

// Minimal SHA-256 used only to name fixture files. This is a deliberately
// short, audited implementation that matches the digest produced by
// `MCTS.Crypto.SHA256`; we keep it self-contained to avoid depending on
// OpenSSL at build time.
namespace sha256 {
constexpr uint32_t K[64] = {
    0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
    0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
    0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
    0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
    0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
    0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
    0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
    0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2};
uint32_t rotr(uint32_t x, int n) { return (x >> n) | (x << (32 - n)); }
std::string hex(const std::vector<uint8_t> &data) {
    uint32_t h[8] = {0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19};
    std::vector<uint8_t> msg = data;
    uint64_t bit_len = static_cast<uint64_t>(data.size()) * 8;
    msg.push_back(0x80);
    while (msg.size() % 64 != 56) msg.push_back(0);
    for (int i = 7; i >= 0; --i) msg.push_back(static_cast<uint8_t>((bit_len >> (8 * i)) & 0xff));
    for (size_t off = 0; off < msg.size(); off += 64) {
        uint32_t w[64];
        for (int i = 0; i < 16; ++i) {
            w[i] = (uint32_t)msg[off + 4 * i] << 24 |
                   (uint32_t)msg[off + 4 * i + 1] << 16 |
                   (uint32_t)msg[off + 4 * i + 2] << 8 |
                   (uint32_t)msg[off + 4 * i + 3];
        }
        for (int i = 16; i < 64; ++i) {
            uint32_t s0 = rotr(w[i - 15], 7) ^ rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
            uint32_t s1 = rotr(w[i - 2], 17) ^ rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
            w[i] = w[i - 16] + s0 + w[i - 7] + s1;
        }
        uint32_t a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
        for (int i = 0; i < 64; ++i) {
            uint32_t S1 = rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25);
            uint32_t ch = (e & f) ^ (~e & g);
            uint32_t t1 = hh + S1 + ch + K[i] + w[i];
            uint32_t S0 = rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22);
            uint32_t mj = (a & b) ^ (a & c) ^ (b & c);
            uint32_t t2 = S0 + mj;
            hh = g; g = f; f = e; e = d + t1; d = c; c = b; b = a; a = t1 + t2;
        }
        h[0]+=a; h[1]+=b; h[2]+=c; h[3]+=d; h[4]+=e; h[5]+=f; h[6]+=g; h[7]+=hh;
    }
    char buf[65]; buf[64] = 0;
    for (int i = 0; i < 8; ++i)
        std::snprintf(buf + i * 8, 9, "%08x", h[i]);
    return std::string(buf);
}
} // namespace sha256

} // namespace

int main(int argc, char **argv) {
    std::string out_root = ".build/legacy-fixtures/transcripts";
    auto require_value = [&](int &index, const char *flag) -> const char * {
        if (index + 1 >= argc) {
            std::fprintf(stderr, "[legacy-to-wire] missing value for %s\n", flag);
            return nullptr;
        }
        ++index;
        return argv[index];
    };

    for (int i = 1; i < argc; ++i) {
        std::string arg = argv[i];
        if (arg == "--output-dir") {
            const char *value = require_value(i, "--output-dir");
            if (value == nullptr) return 2;
            out_root = value;
        } else if (arg == "--seed") {
            const char *value = require_value(i, "--seed");
            if (value == nullptr) return 2;
            REPORT_CARD_SEED = static_cast<uint64_t>(std::stoull(value));
        } else if (arg == "--games") {
            const char *value = require_value(i, "--games");
            if (value == nullptr) return 2;
            REPORT_CARD_GAMES = static_cast<uint32_t>(std::stoul(value));
        } else if (arg == "--sims") {
            const char *value = require_value(i, "--sims");
            if (value == nullptr) return 2;
            REPORT_CARD_SIMS = static_cast<uint32_t>(std::stoul(value));
        } else if (arg == "--max-plies") {
            const char *value = require_value(i, "--max-plies");
            if (value == nullptr) return 2;
            const auto max_plies = static_cast<uint16_t>(std::stoul(value));
            if (max_plies != LEGACY_MAX_PLIES) {
                std::fprintf(stderr, "[legacy-to-wire] --max-plies must be %u\n",
                             static_cast<unsigned>(LEGACY_MAX_PLIES));
                return 2;
            }
        } else if (arg.rfind("--", 0) == 0) {
            std::fprintf(stderr, "[legacy-to-wire] unknown option: %s\n", arg.c_str());
            return 2;
        } else {
            out_root = arg;
        }
    }
    fs::path dir = fs::path(out_root) / arch_dir();
    fs::create_directories(dir);

    for (uint32_t game = 0; game < REPORT_CARD_GAMES; ++game) {
        uint64_t per_game = mix_seed(REPORT_CARD_SEED, static_cast<uint64_t>(game));
        std::fprintf(stderr, "[legacy-to-wire] game %u seed=%llu\n",
                     game, (unsigned long long)per_game);
        GameTranscript transcript = play_one_game(per_game, game);
        std::vector<uint8_t> buf;
        // backend_id = 0 (cpp-legacy)
        encode_header(buf, 0);
        encode_envelope(buf, 0);
        encode_game(buf, transcript);
        std::string sha = sha256::hex(buf);
        fs::path out = dir / (sha + ".tr");
        std::ofstream of(out.string(), std::ios::binary);
        of.write(reinterpret_cast<const char *>(buf.data()),
                 static_cast<std::streamsize>(buf.size()));
        std::fprintf(stderr, "[legacy-to-wire] wrote %s (%zu bytes, %zu moves, winner=%u)\n",
                     out.string().c_str(), buf.size(), transcript.moves.size(),
                     (unsigned)transcript.winner);
    }
    return 0;
}
