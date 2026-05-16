-- CTE 1: Додаємо ранг для кожного снапшота, починаючи з найновішого
WITH latest_ad_snapshots AS (
  SELECT
    source,
    spend,
    impressions,
    clicks,
    installs,
    registrations,
    -- ROW_NUMBER проставляє 1 тільки для останнього за часом рядка по кожному ad_id
    ROW_NUMBER() OVER(
      PARTITION BY ad_id 
      ORDER BY timestamp DESC
    ) AS rn
  FROM `perfect-stock-459407-s8.SKELAR.marketing_ads_raw`
),

-- CTE 2: Агрегуємо фінальні кумулятивні дані та рахуємо базові метрики й CAC
channel_metrics AS (
  SELECT
    source,
    ROUND(SUM(spend), 2) AS total_spend,
    ROUND(SUM(spend) / NULLIF(SUM(impressions), 0) * 1000, 2) AS cpm,
    ROUND(SUM(clicks) / NULLIF(SUM(impressions), 0) * 100, 2) AS ctr_pct,
    ROUND(SUM(installs) / NULLIF(SUM(clicks), 0) * 100, 2) AS cr_click_install_pct,
    ROUND(SUM(registrations) / NULLIF(SUM(installs), 0) * 100, 2) AS cr_install_reg_pct,
    ROUND(SUM(spend) / NULLIF(SUM(registrations), 0), 2) AS cac
  FROM latest_ad_snapshots
  WHERE rn = 1
  GROUP BY 1
),

-- CTE 3: Додаємо LTV для кожного каналу
metrics_with_ltv AS (
  SELECT
    *,
    CASE 
      WHEN source = 'tiktok' THEN 8.50
      WHEN source = 'meta' THEN 6.20
      WHEN source = 'google' THEN 12.40
      ELSE 0 
    END AS ltv
  FROM channel_metrics
)

-- Фінальний крок: Виводимо всі метрики та розраховуємо співвідношення LTV/CAC
SELECT
  source,
  total_spend,
  cpm,
  ctr_pct,
  cr_click_install_pct,
  cr_install_reg_pct,
  cac,
  ltv,
  ROUND(ltv / NULLIF(cac, 0), 2) AS ltv_cac_ratio
FROM metrics_with_ltv
-- Сортуємо від найвищої окупності до найнижчої
ORDER BY ltv_cac_ratio DESC;