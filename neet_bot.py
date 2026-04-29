"""
NEET Rank → College Telegram Bot

Queries PostgREST endpoint /rpc/neet_options_by_rank and returns
available college options for a given NEET All India Rank, category, and quota.

Usage:
    1. Start bot via /start
    2. Enter your NEET All India Rank (integer)
    3. Select Category from inline keyboard (OPEN, SC, ST, OBC, EWS)
    4. Select Quota from inline keyboard
    5. Bot calls API and returns results formatted with Markdown

Environment variables:
    TELEGRAM_BOT_TOKEN  — required, from @BotFather
    API_BASE_URL        — defaults to https://www.neetprep.com/v2api
"""

import os
import logging
from typing import Optional, Dict, Any

import httpx
from telegram import Update, InlineKeyboardButton, InlineKeyboardMarkup
from telegram.ext import (
    Application,
    CallbackQueryHandler,
    CommandHandler,
    ContextTypes,
    ConversationHandler,
    MessageHandler,
    filters,
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("neet_bot")

API_BASE_URL = os.getenv("API_BASE_URL", "https://www.neetprep.com/v2api")
API_ENDPOINT = f"{API_BASE_URL}/rpc/neet_options_by_rank"

# Conversation states
RANK, CATEGORY, QUOTA = range(3)

# Supported categories (normalized codes used by the DB function)
CATEGORIES = ["OPEN", "SC", "ST", "OBC", "EWS"]

# Quota labels offered to the user (subset of the 28 available, most relevant)
QUOTAS = [
    "All India",
    "Open Seat Quota",
    "Delhi University Quota",
    "Deemed/Paid Seats Quota",
    "Aligarh Muslim University (AMU) Quota",
    "Non-Resident Indian",
    "Internal - Puducherry UT Domicile",
    "Delhi NCR Children/Widows of Personnel of the Armed Forces (CW) DU Quota",
    "Employees State Insurance Scheme(ESI)",
    "Jamia Internal Quota",
]


def _quota_short(quota: str) -> str:
    """Return short label for inline keyboard (max 40 chars)."""
    mapping = {
        "All India": "All India",
        "Open Seat Quota": "Open Seat",
        "Delhi University Quota": "DU Quota",
        "Deemed/Paid Seats Quota": "Deemed/Paid",
        "Aligarh Muslim University (AMU) Quota": "AMU Quota",
        "Non-Resident Indian": "NRI",
        "Internal - Puducherry UT Domicile": "Puducherry",
        "Delhi NCR Children/Widows of Personnel of the Armed Forces (CW) DU Quota": "CW DU Quota",
        "Employees State Insurance Scheme(ESI)": "ESI",
        "Jamia Internal Quota": "Jamia",
    }
    return mapping.get(quota, quota[:40])


def build_keyboard(items: list, prefix: str) -> InlineKeyboardMarkup:
    """Build inline keyboard with two columns."""
    buttons = [
        InlineKeyboardButton(item, callback_data=f"{prefix}:{item}")
        for item in items
    ]
    rows = [buttons[i : i + 2] for i in range(0, len(buttons), 2)]
    return InlineKeyboardMarkup(rows)


async def start(update: Update, _: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text(
        "👋 *NEET College Predictor Bot*\n\n"
        "Send me your *NEET All India Rank* (just a number, e.g. `27360`).",
        parse_mode="Markdown",
    )
    return RANK


async def receive_rank(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    text = update.message.text.strip()
    if not text.isdigit():
        await update.message.reply_text("❌ Please enter a valid integer rank (e.g. 27360).")
        return RANK

    context.user_data["rank"] = int(text)
    await update.message.reply_text(
        "📋 *Select your category:*",
        reply_markup=build_keyboard(CATEGORIES, "cat"),
        parse_mode="Markdown",
    )
    return CATEGORY


async def receive_category(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    _, category = query.data.split(":", 1)
    context.user_data["category"] = category

    keyboard = [
        [
            InlineKeyboardButton(
                _quota_short(q), callback_data=f"quota:{q}"
            )
        ]
        for q in QUOTAS
    ]
    keyboard.append([InlineKeyboardButton("Show All Quotas", callback_data="quota:*")])
    await query.edit_message_text(
        f"✅ Category: *{category}*\n\n📋 *Select quota type:*",
        reply_markup=InlineKeyboardMarkup(keyboard),
        parse_mode="Markdown",
    )
    return QUOTA


async def receive_quota(update: Update, context: ContextTypes.DEFAULT_TYPE) -> int:
    query = update.callback_query
    await query.answer()
    _, quota = query.data.split(":", 1)

    rank = context.user_data["rank"]
    category = context.user_data["category"]
    context.user_data["quota"] = quota

    payload: Dict[str, Any] = {
        "p_rank": rank,
        "p_candidate_category": category,
    }

    quota_array: Optional[list] = None
    if quota != "*":
        quota_array = [quota]
    payload["p_quota_labels"] = quota_array

    await query.edit_message_text(
        f"🔎 Fetching colleges for\n"
        f"Rank: *{rank}* | Category: *{category}*\n"
        f"Quota: *{quota if quota != '*' else 'All Quotas'}*",
        parse_mode="Markdown",
    )

    async with httpx.AsyncClient() as client:
        try:
            resp = await client.post(
                API_ENDPOINT, json=payload, timeout=30.0
            )
            resp.raise_for_status()
            rows = resp.json()
        except (httpx.HTTPStatusError, httpx.RequestError) as exc:
            logger.error("API call failed: %s", exc)
            await query.edit_message_text(
                "⚠️ Failed to fetch results. The server may be reloading.\n"
                "Please try again in a minute."
            )
            return ConversationHandler.END

    if not rows:
        await query.edit_message_text(
            f"❌ No colleges found for Rank *{rank}*, Category *{category}*, Quota *{quota}*.",
            parse_mode="Markdown",
        )
        return ConversationHandler.END

    lines = [f"🏥 *Options for Rank {rank} ({category})*\n"]
    for r in rows[:50]:  # Telegram message limit ~4096 chars
        name = r.get("institution_name", "Unknown")
        program = r.get("program_code", "")
        quota_label = r.get("quota_label", "")
        open_r = r.get("opening_rank", "")
        close_r = r.get("closing_rank", "")
        round_key = r.get("round_key", "")
        lines.append(
            f"• *{name}*\n"
            f"  Program: {program} | Quota: {quota_label}\n"
            f"  Open: {open_r} → Close: {close_r} | {round_key}\n"
        )

    message = "\n".join(lines)
    if len(message) > 4000:
        message = message[:4000] + "\n… (truncated, use /start to narrow search)"

    await query.edit_message_text(message, parse_mode="Markdown")
    return ConversationHandler.END


async def cancel(update: Update, _: ContextTypes.DEFAULT_TYPE) -> int:
    await update.message.reply_text("❌ Session cancelled. Send /start to begin again.")
    return ConversationHandler.END


async def help_command(update: Update, _: ContextTypes.DEFAULT_TYPE) -> None:
    await update.message.reply_text(
        "*How to use this bot* 🎓\n\n"
        "1. Send /start\n"
        "2. Enter your NEET All India Rank\n"
        "3. Pick your category (OPEN, SC, ST, OBC, EWS)\n"
        "4. Pick a quota type (All India, Open Seat, etc.)\n"
        "5. Bot returns colleges where closing rank is ≥ your rank\n\n"
        "Send /start any time to restart.",
        parse_mode="Markdown",
    )


def main() -> None:
    token = os.getenv("TELEGRAM_BOT_TOKEN")
    if not token:
        raise RuntimeError("TELEGRAM_BOT_TOKEN environment variable not set")

    app = Application.builder().token(token).build()

    conv = ConversationHandler(
        entry_points=[CommandHandler("start", start)],
        states={
            RANK: [MessageHandler(filters.TEXT & ~filters.COMMAND, receive_rank)],
            CATEGORY: [CallbackQueryHandler(receive_category, pattern=r"^cat:")],
            QUOTA: [CallbackQueryHandler(receive_quota, pattern=r"^quota:")],
        },
        fallbacks=[CommandHandler("cancel", cancel), CommandHandler("start", start)],
    )

    app.add_handler(conv)
    app.add_handler(CommandHandler("help", help_command))

    logger.info("Bot started. Polling for updates…")
    app.run_polling()


if __name__ == "__main__":
    main()
