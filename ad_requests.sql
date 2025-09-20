-- CREATE DATABASE media_publishing;
USE media_publishing;
SELECT * FROM dim_ad_category;
SELECT * FROM dim_city;
SELECT * FROM fact_ad_revenue;
SELECT * FROM fact_city_readiness;
SELECT * FROM fact_digital_pilot;
SELECT * FROM fact_print_sales order by Month;

-- ------------------------------------------------------------------
-- Business Request – 6 : 2021 Readiness vs Pilot Engagement Outlier
-- ------------------------------------------------------------------
WITH readiness AS (
SELECT  r.city_id, DATE_FORMAT(r.quarter, "%Y") AS year,
AVG((r.literacy_rate + r.smartphone_penetration + r.internet_penetration) / 3) AS readiness_score_2021
FROM fact_city_readiness r
GROUP BY year, r.city_id
HAVING year= 2021
),
engagement AS (
    SELECT 
        c.city_id,
        c.city,
        DATE_FORMAT(p.launch_month,"%Y") AS year,
        -- choose one engagement metric here (example: downloads_or_accesses)
        AVG(p.downloads_or_accesses) AS engagement_metric_2021
    FROM fact_digital_pilot p
    JOIN dim_city c ON c.city_id = p.city_id   -- if platform maps to city differently, adjust accordingly
    -- WHERE year = 2021
    GROUP BY year,c.city_id,c.city
    HAVING year= 2021
),
ranked AS (
    SELECT 
        d.city,
        r.readiness_score_2021,
        e.engagement_metric_2021,
        RANK() OVER (ORDER BY r.readiness_score_2021 DESC) AS readiness_rank_desc,
        RANK() OVER (ORDER BY e.engagement_metric_2021 ASC) AS engagement_rank_asc
    FROM readiness r
    JOIN engagement e ON r.city_id = e.city_id
    JOIN dim_city d ON r.city_id = d.city_id
)
SELECT 
    city AS city_name,
    readiness_score_2021,
    engagement_metric_2021,
    readiness_rank_desc,
    engagement_rank_asc,
    CASE 
        WHEN engagement_rank_asc <= 3 
             AND readiness_rank_desc = 1 THEN 'Yes'
        ELSE 'No'
    END AS is_outlier
FROM ranked
ORDER BY readiness_rank_desc, engagement_rank_asc;

-- ------------------------------------------------------------------
-- Business Request – 5: Consistent Multi-Year Decline (2019→2024)  
-- ------------------------------------------------------------------
WITH print_data AS (SELECT  d.city, p.edition_id, p.city_id, DATE_FORMAT(p.Month,"%Y") AS year, SUM(p.net_circulation) AS yearly_net_circulation
FROM fact_print_sales p LEFT JOIN dim_city d ON p.city_id = d.city_id GROUP BY p.edition_id, p.city_id,d.city,year ORDER BY d.city,year ASC),
revenue_data AS (SELECT edition_id, DATE_FORMAT(quarter, "%Y") as year, SUM(ad_revenue) AS yearly_revenue
FROM fact_ad_revenue GROUP BY edition_id, year),
combine AS (SELECT p.city, p.year, p.yearly_net_circulation, r.yearly_revenue
FROM print_data p LEFT JOIN revenue_data r ON p.edition_id = r.edition_id AND p.year = r.year),
lag_data AS(
SELECT 
    city,
    year,
    yearly_net_circulation,
    LAG(yearly_net_circulation,1) OVER(PARTITION BY city) AS prev_circulation,
    yearly_revenue,
    LAG(yearly_revenue,1) OVER(PARTITION BY city) AS prev_revenue
FROM combine),
decline AS (SELECT *,
	CASE 
        WHEN prev_circulation > yearly_net_circulation THEN 'yes'
        WHEN prev_circulation IS NULL THEN NULL
        ELSE 'no'
    END AS is_declining_print,
    CASE 
        WHEN prev_revenue > yearly_revenue THEN 'yes'
        WHEN prev_revenue IS NULL THEN NULL
        ELSE 'no'
    END AS is_declining_revenue
FROM lag_Data)
SELECT city, year, yearly_net_circulation, yearly_revenue, is_declining_print, is_declining_revenue,
	CASE 
        WHEN is_declining_print = 'yes' AND is_declining_revenue = 'yes' THEN 'yes'
        WHEN is_declining_print IS NULL AND is_declining_revenue IS NULL THEN NULL
        ELSE 'no'
    END AS is_declining_both
    FROM decline ORDER BY city, year;
    
-- ------------------------------------------------------------------
-- Business Request – 4 : Internet Readiness Growth (2021) 
-- ------------------------------------------------------------------
WITH temp_data AS (SELECT  d.city, DATE_FORMAT(c.quarter, '%Y-%m') quarter, c.internet_penetration 
FROM fact_city_readiness c LEFT JOIN dim_city d
ON c.city_id=d.city_id
WHERE c.quarter='2020-06-30' OR c.quarter='2021-03-31')
,q1 AS (
    SELECT city, internet_penetration AS internet_rate_q1_2021
    FROM temp_data
    WHERE quarter = '2020-06'
)
,q4 AS (
    SELECT city, internet_penetration AS internet_rate_q4_2021
    FROM temp_data
    WHERE quarter = '2021-03'
)
SELECT 
    q1.city AS city_name,
    q1.internet_rate_q1_2021,
    q4.internet_rate_q4_2021,
    (q4.internet_rate_q4_2021 - q1.internet_rate_q1_2021) AS delta_internet_rate
FROM q1
JOIN q4 ON q1.city = q4.city
ORDER BY delta_internet_rate DESC LIMIT 1;

-- ------------------------------------------------------------------
-- Business Request – 3: 2024 Print Efficiency Leaderboard
-- ------------------------------------------------------------------
WITH temp AS (SELECT d.city, DATE_FORMAT(p.Month, '%Y') as year, (p.Copies_Sold+p.copies_returned) AS copies_printed, p.Net_Circulation 
FROM fact_print_sales p LEFT JOIN dim_city d ON p.city_id = d.city_id)
SELECT city, year, SUM(copies_printed) AS copies_printed_2024, SUM(Net_Circulation) AS Net_Circulation_2024, 
SUM(Net_Circulation)/SUM(copies_printed) AS efficiency_ratio
FROM temp 
WHERE year=2024 GROUP BY city, year ORDER BY efficiency_ratio DESC LIMIT 5;

-- ------------------------------------------------------------------
-- Business Request – 2: Yearly Revenue Concentration by Category
-- ------------------------------------------------------------------
WITH revenue AS (SELECT DATE_FORMAT(quarter, '%Y') as year, ad_category AS category_name, SUM(ad_revenue) as category_revenue
FROM fact_ad_revenue group by category_name, year),
yearly_revenue AS(SELECT year, SUM(category_revenue) as total_revenue_year FROM revenue
GROUP BY year)
SELECT r.year, r.category_name, r.category_revenue, yr.total_revenue_year, (r.category_revenue/yr.total_revenue_year)*100 AS pct_of_year_total
FROM revenue r LEFT JOIN yearly_revenue yr ON r.year = yr.year;

-- ------------------------------------------------------------------
-- Business Request – 1: Monthly Circulation Drop Check 
-- ------------------------------------------------------------------
WITH revenue AS(SELECT DATE_FORMAT(quarter, '%Y') as year, ad_category AS category_name, SUM(ad_revenue) as total_revenue_year
-- ,(SELECT SUM(ad_revenue) FROM fact_ad_revenue) as total_revenue_year
FROM fact_ad_revenue group by year)
SELECT year, category_name, category_revenue, total_revenue_year, (category_revenue/total_revenue_year) * 100 AS pct_of_year_total FROM revenue;

WITH circulation_with_lag AS(
SELECT c.city, DATE_FORMAT(p.Month, '%Y-%m') AS month, p.Net_Circulation,
LAG(p.Net_Circulation) OVER (PARTITION BY c.city ORDER BY p.month) AS prev_net_circulation 
FROM fact_print_sales p
LEFT JOIN dim_city c ON p.City_ID = c.city_id),
declines AS (
    SELECT
        city,
        month,
        Net_Circulation,
        (Net_Circulation - prev_net_circulation) AS change_in_circulation
    FROM circulation_with_lag
    WHERE prev_net_circulation IS NOT NULL
)
SELECT 
    city,
    month,
    Net_Circulation,
    change_in_circulation
FROM declines
WHERE change_in_circulation < 0   -- only declines
ORDER BY change_in_circulation ASC   -- biggest negative drop
LIMIT 3;
