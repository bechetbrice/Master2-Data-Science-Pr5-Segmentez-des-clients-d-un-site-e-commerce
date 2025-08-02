/*
Script SQL pour le projet Olist - Segmentation des clients
Brice Béchet - Avril 2025

Ce script contient les 4 requêtes demandées par Fernanda pour le dashboard Customer Experience:
1. Commandes récentes livrées avec au moins 3 jours de retard
2. Vendeurs ayant généré plus de 100 000 Real de chiffre d'affaires
3. Nouveaux vendeurs très engagés sur la plateforme
4. Codes postaux avec les pires évaluations moyennes
*/

-- REQUÊTE 1: COMMANDES RÉCENTES LIVRÉES AVEC AU MOINS 3 JOURS DE RETARD
-- Cette requête identifie les commandes des 3 derniers mois non annulées 
-- dont la livraison a été effectuée avec au moins 3 jours de retard

WITH recent_orders AS (
    -- Sélection des commandes non annulées des 3 derniers mois
    SELECT *
    FROM orders
    WHERE order_status != 'canceled'
    AND order_purchase_timestamp >= (
        -- Calcul de la date limite (3 mois avant la date la plus récente)
        -- La fonction DATE() avec un modificateur '-3 months' permet de soustraire 3 mois à la date maximale
        SELECT DATE(MAX(order_purchase_timestamp), '-3 months')
        FROM orders
    )
),
delayed_orders AS (
    -- Identification et calcul des retards de livraison
    SELECT
        order_id,
        order_purchase_timestamp,
        order_delivered_customer_date,
        order_estimated_delivery_date,
        -- JULIANDAY() convertit les dates en jours juliens pour permettre un calcul précis
        -- de la différence entre deux dates (y compris les heures, minutes, secondes)
        JULIANDAY(order_delivered_customer_date) - JULIANDAY(order_estimated_delivery_date) AS delay_days
    FROM recent_orders
    WHERE order_delivered_customer_date IS NOT NULL  -- Exclusion des commandes non livrées
    AND order_estimated_delivery_date IS NOT NULL   -- Exclusion des commandes sans date estimée
    -- Vérification que la livraison est postérieure à la date estimée
    AND JULIANDAY(order_delivered_customer_date) > JULIANDAY(order_estimated_delivery_date)
    -- Filtrage pour ne retenir que les retards d'au moins 3 jours
    AND JULIANDAY(order_delivered_customer_date) - JULIANDAY(order_estimated_delivery_date) >= 3
)
-- Affichage des résultats triés par date d'achat décroissante
SELECT * FROM delayed_orders
ORDER BY order_purchase_timestamp DESC;

-- ****************************************************************************************
-- REQUÊTE 2: VENDEURS AYANT GÉNÉRÉ PLUS DE 100 000 REAL DE CHIFFRE D'AFFAIRES
-- Cette requête identifie les vendeurs dont les commandes livrées ont généré un CA supérieur à 100 000 Real

WITH seller_revenue AS (
    -- Calcul du chiffre d'affaires total par vendeur
    -- Prend en compte uniquement le prix des produits, sans les frais de livraison
    SELECT
        s.seller_id,
        s.seller_city,
        s.seller_state,
        SUM(oi.price) AS total_revenue
    FROM order_items oi
    JOIN sellers s ON oi.seller_id = s.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    -- Filtrage pour ne considérer que les commandes effectivement livrées
    WHERE o.order_status = 'delivered'
    -- Regroupement par vendeur pour calculer le CA total de chacun
    GROUP BY s.seller_id, s.seller_city, s.seller_state
    -- Sélection des vendeurs dépassant le seuil de 100 000 Real
    HAVING total_revenue > 100000
)
-- Requête finale pour afficher les résultats formatés
SELECT
    seller_id,
    seller_city,
    seller_state,
    -- Arrondi du chiffre d'affaires à 2 décimales pour une meilleure lisibilité
    ROUND(total_revenue, 2) AS total_revenue_real
FROM seller_revenue
-- Tri par chiffre d'affaires décroissant pour identifier facilement les plus performants
ORDER BY total_revenue DESC;

-- ****************************************************************************************
-- REQUÊTE 3: NOUVEAUX VENDEURS TRÈS ENGAGÉS SUR LA PLATEFORME
-- Cette requête identifie les vendeurs récents (moins de 3 mois d'ancienneté) 
-- ayant déjà vendu plus de 30 produits

WITH seller_first_order AS (
    -- Détermination de la date de première commande pour chaque vendeur
    SELECT
        s.seller_id,
        MIN(o.order_purchase_timestamp) AS first_order_date
    FROM sellers s
    JOIN order_items oi ON s.seller_id = oi.seller_id
    JOIN orders o ON oi.order_id = o.order_id
    GROUP BY s.seller_id
),
recent_sellers AS (
    -- Filtrage pour ne conserver que les vendeurs récents (moins de 3 mois)
    SELECT
        sfo.seller_id
    FROM seller_first_order sfo
    WHERE sfo.first_order_date >= (
        -- Calcul de la date limite (3 mois avant la date la plus récente)
        SELECT DATE(MAX(order_purchase_timestamp), '-3 months')
        FROM orders
    )
),
seller_products_count AS (
    -- Comptage du nombre de produits vendus par les nouveaux vendeurs
    SELECT
        rs.seller_id,
        COUNT(oi.product_id) AS products_sold,
        s.seller_city,
        s.seller_state
    FROM recent_sellers rs
    JOIN order_items oi ON rs.seller_id = oi.seller_id
    JOIN sellers s ON rs.seller_id = s.seller_id
    -- Regroupement par vendeur pour calculer le nombre total de produits vendus
    GROUP BY rs.seller_id, s.seller_city, s.seller_state
    -- Filtrage pour ne garder que les vendeurs ayant vendu plus de 30 produits
    HAVING products_sold > 30
)
-- Requête finale pour afficher les résultats
SELECT
    seller_id,
    seller_city,
    seller_state,
    products_sold
FROM seller_products_count
-- Tri par nombre de produits vendus décroissant
ORDER BY products_sold DESC;

-- ****************************************************************************************
-- REQUÊTE 4: CODES POSTAUX AVEC LES PIRES ÉVALUATIONS MOYENNES
-- Cette requête identifie les 5 codes postaux ayant reçu plus de 30 avis
-- et présentant les scores d'évaluation moyenne les plus bas sur les 12 derniers mois

WITH recent_reviews AS (
    -- Sélection des avis des 12 derniers mois avec jointure pour obtenir les informations client
    SELECT
        r.*,
        o.customer_id,
        o.order_purchase_timestamp
    FROM order_reviews r
    JOIN orders o ON r.order_id = o.order_id
    WHERE o.order_purchase_timestamp >= (
        -- Calcul de la date limite (12 mois avant la date la plus récente)
        SELECT DATE(MAX(order_purchase_timestamp), '-12 months')
        FROM orders
    )
),
zip_reviews AS (
    -- Calcul du score moyen et du nombre total d'avis par code postal
    SELECT
        c.customer_zip_code_prefix,
        AVG(r.review_score) AS avg_review_score,
        COUNT(r.review_id) AS total_reviews
    FROM recent_reviews r
    JOIN customers c ON r.customer_id = c.customer_id
    -- Regroupement par code postal
    GROUP BY c.customer_zip_code_prefix
    -- Filtrage pour ne conserver que les codes postaux avec plus de 30 avis
    HAVING total_reviews > 30
)
-- Requête finale pour afficher les 5 codes postaux avec les pires scores
SELECT
    customer_zip_code_prefix,
    ROUND(avg_review_score, 2) AS avg_review_score,
    total_reviews
FROM zip_reviews
-- Tri par score d'évaluation croissant (les pires en premier)
ORDER BY avg_review_score ASC
-- Limitation aux 5 premiers résultats
LIMIT 5;