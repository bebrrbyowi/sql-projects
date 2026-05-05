/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Горюнова Полина Александровна
 * Дата: 28.04.2026
*/
-- Часть 1. Разработка витрины данных

CREATE TABLE ds_ecom.product_user_features AS
-- расчет полной стоимости заказа (товары + доставка) на уровне order_id
WITH op AS (SELECT order_id, BUYER_ID, sum (COALESCE(price, 0) + COALESCE(delivery_cost, 0)) AS order_price, order_purchase_ts, order_status
FROM ds_ecom.orders
LEFT JOIN ds_ecom.order_items
	USING (order_id)
GROUP BY order_id, buyer_id, order_purchase_ts, order_status
), 
-- расчет пользовательских метрик по заказам (еще на уровне заказов)
ooo AS (
SELECT user_id, region, order_id, order_status, min (order_purchase_ts) OVER (PARTITION BY user_id, region) AS first_order_ts, max (order_purchase_ts) OVER (PARTITION BY user_id, region) AS last_order_ts, count (order_id) OVER (PARTITION BY user_id, region) AS total_orders, sum (CASE WHEN order_status = 'Доставлено' THEN order_price
WHEN order_status = 'Отменено' THEN 0 END) OVER (PARTITION BY user_id, region) AS total_order_costs, AVG(CASE 
    WHEN order_status = 'Доставлено' THEN order_price 
END) OVER (PARTITION BY user_id, region) AS avg_order_cost, count (CASE WHEN order_status = 'Отменено' THEN 1 END) OVER (PARTITION BY user_id, region) AS num_canceled_orders
FROM op
JOIN ds_ecom.users
	USING (buyer_id)
WHERE order_status IN ('Доставлено', 'Отменено')
), 
-- формирование признаков по оплате на уровне заказа (рассрочка, промокод, первый тип оплаты)
order_p AS (
    SELECT order_id, MAX(CASE WHEN payment_installments > 1 THEN 1 ELSE 0 END) AS incount, MAX(CASE WHEN payment_type = 'промокод' THEN 1 ELSE 0 END) AS cpromo, MAX(CASE 
            WHEN payment_sequential = 1 
                 AND payment_type = 'денежный перевод' 
            THEN 1 ELSE 0 
        END) AS used_money_transferr
FROM ds_ecom.order_payments
GROUP BY order_id
), 
-- объединение заказов и платежей + расчет пользовательских метрик и бинарных признаков
base AS (SELECT user_id, region, first_order_ts, last_order_ts, order_id, used_money_transferr, last_order_ts - first_order_ts AS lifetime, total_orders, num_canceled_orders, num_canceled_orders * 1.0 / total_orders AS canceled_orders_ratio, total_order_costs, avg_order_cost, SUM(incount) OVER (PARTITION BY user_id, region) AS num_installment_orders, SUM(cpromo) OVER (PARTITION BY user_id, region) AS num_orders_with_promo, CASE 
WHEN num_canceled_orders >= 1 THEN 1
ELSE 0
END AS used_cancel
FROM ooo
LEFT JOIN order_p
	USING (order_id)),
-- нормализация рейтинга (приведение шкалы 10–50 к 1–5) и расчет среднего рейтинга заказа
rating AS (
    SELECT order_id, AVG(
    CASE 
        WHEN review_score IN (10, 20, 30, 40, 50) THEN review_score / 10
        WHEN review_score BETWEEN 1 AND 5 THEN review_score
        ELSE NULL
    END
) AS score
FROM ds_ecom.order_reviews
GROUP BY order_id
), 
-- добавление рейтинговых метрик и финальных бинарных признаков на уровне пользователь–регион
full_base AS (SELECT *, avg (score) OVER (PARTITION BY user_id, region) AS avg_order_rating, COUNT(CASE WHEN score IS NOT NULL THEN 1 END) OVER (PARTITION BY user_id, region) AS num_orders_with_rating, CASE 
WHEN num_installment_orders >= 1 THEN 1
ELSE 0
END AS used_installments, MAX(used_money_transferr) OVER (PARTITION BY user_id, region) AS used_money_transfer
FROM base
LEFT JOIN rating
	USING (order_id)), 
-- определение топ-3 регионов по количеству заказов
top_regions AS (
    SELECT region
FROM ds_ecom.orders
JOIN ds_ecom.users
	USING (buyer_id)
WHERE order_status IN ('Доставлено', 'Отменено')
GROUP BY region
ORDER BY COUNT(order_id) DESC
LIMIT 3
), 
-- финальная агрегация до уровня "пользователь–регион" (устранение дублей)
FINAL AS (
    SELECT user_id, region, MIN(first_order_ts) AS first_order_ts, MAX(last_order_ts) AS last_order_ts, MAX(lifetime) AS lifetime, MAX(total_orders) AS total_orders, AVG(avg_order_rating) AS avg_order_rating, MAX(num_orders_with_rating) AS num_orders_with_rating, MAX(num_canceled_orders) AS num_canceled_orders, MAX(canceled_orders_ratio) AS canceled_orders_ratio, MAX(total_order_costs) AS total_order_costs, MAX(avg_order_cost) AS avg_order_cost, MAX(num_installment_orders) AS num_installment_orders, MAX(num_orders_with_promo) AS num_orders_with_promo, MAX(used_money_transfer) AS used_money_transfer, MAX(used_installments) AS used_installments, MAX(used_cancel) AS used_cancel
FROM full_base
GROUP BY user_id, region
)
SELECT *
FROM FINAL
WHERE region IN (SELECT region
FROM top_regions)


/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

WITH segmentation AS (SELECT user_id, region, total_order_costs, total_orders,
CASE 
	WHEN total_orders = 1 THEN '1 заказ'
	WHEN total_orders BETWEEN 2 AND 5 THEN '2 — 5 заказов'
	WHEN total_orders BETWEEN 6 AND 10 THEN '6 — 10 заказов'
	WHEN total_orders >=11 THEN '11 и более заказов'
END AS segment
FROM ds_ecom.product_user_features)
SELECT segment, 
count (DISTINCT user_id) AS user_count,
avg (total_orders) AS avg_orders,
sum (total_order_costs) * 1.0 / sum (total_orders) AS avg_order_price
FROM segmentation
GROUP BY segment;

/* Напишите краткий комментарий с выводами по результатам задачи 1.

  Преобладающее большинство пользователей совершают лишь один заказ (примерно 60000 человек),
средний чек у этого сегмента самый высокий. Только один человек совершил 11+ заказов.



/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

SELECT 
user_id, 
region, 
total_order_costs, 
total_orders,
total_order_costs * 1.0 / total_orders AS avg_cost
FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_cost DESC
LIMIT 15;

/* Напишите краткий комментарий с выводами по результатам задачи 2.
 * 
В выборке доминируют пользователи с небольшим числом заказов (3–5), но высоким средним чеком. 
Это указывает на сегмент клиентов, совершающих редкие, но дорогостоящие покупки. Средний данных пользователей чек выше, чем средний чек по каждому региону.




/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

SELECT 
    region, 
    count (user_id) AS users,  
    sum (total_orders) AS orders,
    sum (total_order_costs) * 1.0 / sum (total_orders) AS avg_cost,
    sum (num_installment_orders) * 1.0 / sum (total_orders) AS installment_share,
    sum (num_orders_with_promo) * 1.0 / sum (total_orders) AS promo_share,
    sum (used_cancel) * 1.0 / count (user_id) AS cancel_user_share
FROM ds_ecom.product_user_features
GROUP BY region;

/* Напишите краткий комментарий с выводами по результатам задачи 3.
 
*Москва - главный рынок по числу клиентов и заказов, но средний чек там ниже, чем в других регионах. 
В Санкт-Петербурге и Новосибирской области покупают реже, но на более крупные суммы. 
Рассрочку чаще используют в Санкт-Петербурге и Новосибирской области, чем в Москве. 
Промокоды и отмены почти одинаково низкие во всех регионах и не дают сильных различий.




/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/
WITH aaa AS (SELECT 
user_id,
region,
DATE_TRUNC('month', first_order_ts) AS u_month,
total_orders,
total_order_costs,
avg_order_rating,
used_money_transfer,
lifetime
FROM ds_ecom.product_user_features
WHERE first_order_ts >= '2023-01-01' AND first_order_ts <  '2024-01-01')
SELECT 
u_month,
count (DISTINCT user_id) AS users,
sum (total_orders) AS orders,
sum (total_order_costs) * 1.0 / sum (total_orders) AS avg_order_price,
avg (avg_order_rating) AS avg_rating,
sum (used_money_transfer) * 1.0 / count (user_id) AS money_transfer_share,
avg (lifetime) AS avg_lifetime
FROM aaa
GROUP BY u_month
ORDER BY u_month;

--Напишите краткий комментарий с выводами по результатам задачи 4.
-- В 2023 году число новых пользователей заметно выросло к концу года, особенно в ноябре и декабре. 
-- Средний чек в целом стабильный, но в осенне-зимние месяцы он становится выше. 
 --Оценки сервиса остаются примерно одинаковыми на протяжении года.
