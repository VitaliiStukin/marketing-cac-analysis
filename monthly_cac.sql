-- CTE 1: Додаємо ранг для кожного снапшота кожного ad_id в озрізі місяця.
WITH monthly_snapshots AS (
  SELECT
    source,
    -- FORMAT_DATE групує всі дати місяця в один текстовий рядок 'YYYY-MM'
    FORMAT_DATE('%Y-%m', date) AS month,
    ad_id,
    spend,
    clicks,
    registrations,
    -- ROW_NUMBER проставляє 1 для найсвіжішого запису оголошення в межах конкретного місяця
    ROW_NUMBER() OVER(
      PARTITION BY ad_id, FORMAT_DATE('%Y-%m', date) 
      ORDER BY date DESC, timestamp DESC
    ) AS rn
  FROM `perfect-stock-459407-s8.SKELAR.marketing_ads_raw`
),

-- CTE 2: Розраховуємо чистий приріст метрик за місяць за допомогою LAG.
-- Від кумулятивного значення на кінець цього місяця віднімаємо значення на кінець попереднього місяця.
monthly_increments AS (
  SELECT
    month,
    source,
    -- COALESCE замінює NULL на 0, якщо оголошення тільки запустилося і попереднього місяця не існує
    spend - COALESCE(LAG(spend) OVER(PARTITION BY ad_id ORDER BY month), 0) AS monthly_spend,
    clicks - COALESCE(LAG(clicks) OVER(PARTITION BY ad_id ORDER BY month), 0) AS monthly_clicks,
    registrations - COALESCE(LAG(registrations) OVER(PARTITION BY ad_id ORDER BY month), 0) AS monthly_regs
  FROM monthly_snapshots
  WHERE rn = 1 -- залишаємо тільки один фінальний snapshot на ad_id за місяць
),

-- CTE 3: Сумуємо чисті щомісячні прирости всіх оголошень до рівня каналу.
monthly_channel_aggregates AS (
  SELECT
    month,
    source,
    SUM(monthly_clicks) AS clicks,
    SUM(monthly_regs) AS registrations,
    -- Рахуємо точний неокруглений CAC місяця, щоб зберегти точність для наступних віконних функцій
    -- NULLIF рятує від помилки 'division by zero', якщо в якомусь місяці не було реєстрацій
    SUM(monthly_spend) / NULLIF(SUM(monthly_regs), 0) AS raw_cac
  FROM monthly_increments
  GROUP BY 1, 2
)

-- Фінальний крок: Розраховуємо екстремуми та відсоток відхилення.
SELECT
  month,
  source,
  -- Округляємо фактичний CAC місяця для фінального звіту
  ROUND(raw_cac, 2) AS cac,
  
  -- MAX() OVER шукає найвищий точний щомісячний CAC для каналу за весь період
  ROUND(MAX(raw_cac) OVER(PARTITION BY source), 2) AS max_cac_ever,
  
  -- MIN() OVER шукає найнижчий точний щомісячний CAC для каналу за весь період
  ROUND(MIN(raw_cac) OVER(PARTITION BY source), 2) AS min_cac_ever,
  
  -- Формула відхилення у відсотках працює з точними (неокругленими) числами
  ROUND(
    (1 - (MIN(raw_cac) OVER(PARTITION BY source) / NULLIF(MAX(raw_cac) OVER(PARTITION BY source), 0))) * 100, 
    2
  ) AS cac_variance_pct,
  
  -- Кліки та реєстрації виводимо в самому кінці за вимогою бізнесу
  clicks,
  registrations
FROM monthly_channel_aggregates
ORDER BY source ASC, month ASC;