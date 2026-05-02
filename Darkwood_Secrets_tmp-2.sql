/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Горюнова Полина Александровна
 * Дата: 26.04.2026
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
SELECT 
    COUNT(CASE WHEN payer = 1 THEN 1 END) AS pay_id ,
    COUNT(*) AS all_id,
    COUNT(CASE WHEN payer = 1 THEN 1 END) * 1.0 / COUNT(*) AS payer_fraction
FROM fantasy.users;

-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
WITH base AS (SELECT 
    race_id,
    COUNT(id) AS race_count,
    COUNT (CASE WHEN payer = 1 THEN '1' END) AS payers
FROM fantasy.users
GROUP BY race_id
)
SELECT *, 
payers*1.0/race_count AS fraction
FROM base;

-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT COUNT (*), 
SUM (amount),
MAX (amount), 
MIN (amount),
AVG (amount), 
PERCENTILE_DISC (0.5) WITHIN GROUP (ORDER BY amount) AS median,
STDDEV (amount)
FROM fantasy.events;

-- 2.2: Аномальные нулевые покупки:
WITH base AS (SELECT count (*) AS all_count, 
count (CASE WHEN amount = 0 THEN 1 END ) AS zero_amount
FROM fantasy.events
)
SELECT *, ZERO_AMOUNT * 1.0 / ALL_COUNT 
FROM base;

-- 2.3: Популярные эпические предметы:
WITH base AS (
    SELECT 
        ITEM_CODE, 
        COUNT(*) AS abs_sell,
        COUNT(DISTINCT id) AS buyers
    FROM fantasy.events	
    WHERE amount <> 0
    GROUP BY ITEM_CODE 
),
players AS (
    SELECT COUNT(DISTINCT id) AS total_players
    FROM fantasy.events
)
SELECT *, 
abs_sell * 1.0 / sum (abs_sell) OVER () AS fraction,
buyers * 1.0 / (SELECT total_players FROM players) AS fraction_buyers
FROM base
ORDER BY fraction DESC;

-- Часть 2. Решение ad hoc-задачbи
-- Задача: Зависимость активности игроков от расы персонажа:
WITH base AS (
    SELECT 
        users.id,
        users.race_id,
        users.payer,
        COUNT(CASE WHEN amount > 0 THEN 1 END) AS buy_count,
        SUM(CASE WHEN amount > 0 THEN amount END) AS total_amount
    FROM fantasy.users
    LEFT JOIN fantasy.events 
        ON users.id = events.id
    GROUP BY users.id, race_id, payer
)
SELECT 
    race_id,
    COUNT(*) AS total_users,
    COUNT(CASE WHEN buy_count > 0 THEN 1 END) AS payers_count,
    COUNT(CASE WHEN buy_count > 0 THEN 1 END) * 1.0 / COUNT(*) AS payers_fraction,
    COUNT(CASE WHEN buy_count > 0 AND payer = 1 THEN 1 END) * 1.0 / COUNT(CASE WHEN buy_count > 0 THEN 1 END) AS payers_of_buyers,
    AVG(CASE WHEN buy_count > 0 THEN buy_count END) AS avg_count,
    SUM(total_amount) * 1.0 / SUM(buy_count) AS avg_purchase_amount,
    AVG(CASE WHEN buy_count > 0 THEN total_amount END) AS avg_total_amount_per_buyer
FROM base
GROUP BY race_id;
