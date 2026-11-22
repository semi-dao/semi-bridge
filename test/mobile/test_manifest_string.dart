// 測試用 Tier manifest 字串（同步建 registry，避免 rootBundle 非同步卡死）
// 內容 = assets/theme_packs/bridge_default_v2.json 的逐字副本
// [S4 2026-11-10] 由小葵產生——若 manifest 改版請重新產生本檔

class TestManifestString {
  static final String bridgeDefault =
      r'''{
  "id": "bridge_default_v2",
  "name": "橋樑預設 v2",
  "version": "1.0.0",
  "author": "Bridge Team",
  "license": "MIT",
  "minBridgeVersion": "1.0.0",
  "targetModes": [
    "dark"
  ],
  "fonts": {
    "base": "Inter",
    "mono": "JetBrainsMono"
  },
  "tokens": {
    "canvas": "#07080A",
    "surface": "#101111",
    "surfaceElevated": "#1B1C1E",
    "surfaceHover": "#252829",
    "borderSubtle": "#0FFFFFFF",
    "borderDefault": "#1AFFFFFF",
    "textPrimary": "#F9F9F9",
    "textSecondary": "#CECECE",
    "textMuted": "#6A6B6C",
    "accentBlue": "#55B3FF",
    "accentPurple": "#533AFD",
    "accentGreen": "#5FC992",
    "accentYellow": "#FFBC33",
    "accentRed": "#FF6363",
    "accentNavy": "#061B31",
    "accentMagenta": "#F96BEE",
    "accentRuby": "#EA2261",
    "accentMiro": "#5B76FE",
    "success": "#5FC992",
    "warning": "#FFBC33",
    "error": "#FF6363",
    "info": "#55B3FF"
  },
  "tiers": {
    "app.title": {
      "textColor": "textPrimary",
      "fontSize": 24,
      "fontWeight": "w700",
      "fontFamily": "base",
      "lineHeight": 1.4
    },
    "app.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 16,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "sidebar.row.title": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "sidebar.row.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 13,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "sidebar.row.meta": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "mono"
    },
    "card.title": {
      "textColor": "textPrimary",
      "fontSize": 16,
      "fontWeight": "w700",
      "fontFamily": "base"
    },
    "card.body": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base",
      "lineHeight": 1.6
    },
    "card.caption": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "list.item.title": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "list.item.subtitle": {
      "textColor": "textSecondary",
      "fontSize": 13,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "list.item.meta": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "mono"
    },
    "form.label": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "form.input": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "form.helper": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "dialog.title": {
      "textColor": "textPrimary",
      "fontSize": 18,
      "fontWeight": "w700",
      "fontFamily": "base"
    },
    "dialog.body": {
      "textColor": "textSecondary",
      "fontSize": 14,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "button.primary": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w600",
      "fontFamily": "base"
    },
    "button.secondary": {
      "textColor": "textSecondary",
      "fontSize": 14,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "status.success": {
      "textColor": "success",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "status.warning": {
      "textColor": "warning",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "status.error": {
      "textColor": "error",
      "fontSize": 14,
      "fontWeight": "w600"
    },
    "status.info": {
      "textColor": "info",
      "fontSize": 14,
      "fontWeight": "w500"
    },
    "bg.panel.base": {
      "bgColor": "canvas"
    },
    "bg.panel.elevated": {
      "bgColor": "surfaceElevated"
    },
    "bg.panel.hover": {
      "bgColor": "surfaceHover"
    },
    "bg.panel.selected": {
      "bgColor": "accentBlue"
    },
    "border.subtle": {
      "borderColor": "borderSubtle",
      "borderWidth": 1
    },
    "border.default": {
      "borderColor": "borderDefault",
      "borderWidth": 1
    },
    "border.strong": {
      "borderColor": "textPrimary",
      "borderWidth": 2
    },
    "card.caption.heavy": {
      "textColor": "textMuted",
      "fontSize": 12,
      "fontWeight": "w900"
    },
    "card.caption.bold": {
      "textColor": "textPrimary",
      "fontSize": 12,
      "fontWeight": "w700"
    },
    "card.caption.emphasized": {
      "textColor": "textSecondary",
      "fontSize": 14,
      "fontWeight": "w700"
    },
    "step.summary": {
      "textColor": "accentBlue",
      "fontSize": 12,
      "fontWeight": "w500"
    },
    "block.heading": {
      "textColor": "textPrimary",
      "fontSize": 18,
      "fontWeight": "w700"
    },
    "block.subheading": {
      "textColor": "textPrimary",
      "fontSize": 14,
      "fontWeight": "w700"
    },
    "numeric.emphasis": {
      "textColor": "accentYellow",
      "fontSize": 12,
      "fontWeight": "w900"
    },
    "app.displayLarge": {
      "textColor": "textPrimary",
      "fontSize": 32,
      "fontWeight": "w400",
      "fontFamily": "display"
    },
    "app.headline": {
      "textColor": "textPrimary",
      "fontSize": 24,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "card.heroTitle": {
      "textColor": "textPrimary",
      "fontSize": 20,
      "fontWeight": "w500",
      "fontFamily": "base"
    },
    "body.primary": {
      "textColor": "textPrimary",
      "fontSize": 18,
      "fontWeight": "w400",
      "fontFamily": "base",
      "height": 1.5
    },
    "ceremony.heroTitle": {
      "textColor": "textPrimary",
      "fontSize": 28,
      "fontWeight": "w700",
      "fontFamily": "base"
    },
    "ceremony.heroEmoji": {
      "textColor": "textPrimary",
      "fontSize": 80,
      "fontWeight": "w400",
      "fontFamily": "base"
    },
    "ceremony.cta": {
      "textColor": "textPrimary",
      "fontSize": 16,
      "fontWeight": "w700",
      "fontFamily": "base",
      "letterSpacing": 4.0
    },
    "ceremony.callToAction": {
      "textColor": "textPrimary",
      "fontSize": 16,
      "fontWeight": "w700",
      "fontFamily": "base",
      "letterSpacing": 2.0
    },
    "ceremony.code": {
      "textColor": "textPrimary",
      "fontSize": 28,
      "fontWeight": "w900",
      "fontFamily": "base"
    }
  }
}
''';
}
