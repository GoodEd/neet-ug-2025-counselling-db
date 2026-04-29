# NEET College Predictor Telegram Bot 🤖

Telegram bot that predicts available colleges for a given NEET All India Rank, category, and quota type.

## Architecture

```
User → Telegram Bot → PostgREST → PostgreSQL
                    ↑
            api.neet_colleges_text()
            (returns formatted Markdown)
```

## Setup

### 1. Environment Variables

```bash
export TELEGRAM_BOT_TOKEN="your:bot_token"
export API_BASE_URL="https://www.neetprep.com/v2api"
```

### 2. Install Dependencies

```bash
pip install python-telegram-bot httpx
```

### 3. Run Bot

```bash
python neet_bot.py
```

## How to Use

1. Start bot with `/start`
2. Enter your NEET All India Rank (e.g. `27360`)
3. Select category from inline keyboard (OPEN, SC, ST, OBC, EWS)
4. Select quota type (All India, Open Seat, DU Quota, etc.)
5. Bot fetches and displays available colleges formatted with Markdown

## PostgREST API

### Text API (Recommended for Bots)

- **Endpoint**: `POST /rpc/neet_colleges_text`
- **Returns**: Formatted Markdown text
- **Body**:

```json
{
  "p_rank": 27360,
  "p_candidate_category": "OPEN",
  "p_quota_label": "All India"
}
```

### JSON API (Raw Data)

- **Endpoint**: `POST /rpc/neet_options_by_rank`
- **Returns**: JSON array of rows
- **Body**:

```json
{
  "p_rank": 27360,
  "p_candidate_category": "OPEN",
  "p_quota_labels": ["All India", "Open Seat Quota"]
}
```

## Quota Types Supported

| Quota Label | Description |
|-------------|-------------|
| All India | All India Quota |
| Open Seat Quota | Open Seat |
| Delhi University Quota | DU Quota |
| Deemed/Paid Seats Quota | Deemed/Paid |
| Aligarh Muslim University (AMU) Quota | AMU |
| Non-Resident Indian | NRI |
| Jamia Internal Quota | Jamia |
| ... | See `QUOTAS` table in `neetcounselling2025` schema |

## Data Flow

```
PostgREST (api schema)
    → api.neet_colleges_text()
        → neetcounselling2025.fn_available_options_by_rank()
            → round_cutoff, institution, program, quota tables
```

`api.neet_colleges_text` is `SECURITY DEFINER` so it can query the private `neetcounselling2025` schema without exposing DB credentials to the bot.

## PostgREST Cache Issue

When creating new functions, PostgREST needs schema cache reload:

```bash
# Restart PostgREST after deploying new functions
docker restart <postgrest-container>
```

## Files

| File | Purpose |
|------|---------|
| `neet_bot.py` | Telegram bot |
| `sql/neet_colleges_text.sql` | Text-returning API function |
| `sql/neetcounselling2025/schema.sql` | Full database schema |
