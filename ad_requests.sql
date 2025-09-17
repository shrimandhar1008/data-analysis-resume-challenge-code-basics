-- CREATE DATABASE media_publishing;
USE media_publishing;
SELECT * FROM dim_ad_category;
SELECT * FROM dim_city;
SELECT * FROM fact_ad_revenue;
SELECT * FROM fact_city_readiness;
SELECT * FROM fact_digital_pilot;
SELECT * FROM fact_print_sales order by Month;

-- ------------------------------------------------------------------
-- Business Request – 5: Consistent Multi-Year Decline (2019→2024)  
-- ------------------------------------------------------------------

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
