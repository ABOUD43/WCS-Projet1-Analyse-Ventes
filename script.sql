--  Affiche toutes les bases de données disponibles
show DATABASES ; 
-- Selectionne la base de données(BD) "toys_and_models" pour excuter les requetes 
use toys_and_models; 

-- Appereçu sur les données 
select * from orderdetails;
select * from products;
select * from orders;
select * from products;
select * from productlines;
select * from customers;
select * from employees;
select * from offices;

-- Question : Le nombre de produits vendus par catégorie et par mois, avec comparaison et taux d'évolution par rapport au même mois de l'année précédente.

-- Etape 1 : le nombre de produits vendus par catégorie et par mois 
 select 
 MONTH(orders.orderDate) as month_ordre , -- Mois de la commande 
 YEAR(orders.orderDate) as year_ordre, -- Année de la commande 
 products.productLine as category,  -- Catégorie du produit
sum(orderdetails.quantityOrdered) as Total_product_sales -- Total de produits vendus
from orderdetails 
join orders
on orders.orderNumber = orderdetails.orderNumber
join products
on products.productCode = orderdetails.productCode
group by YEAR(orders.orderDate), MONTH(orders.orderDate), products.productLine; -- Regroupement par année, mois et catégorie

-- Etape 2 :Comparaison et taux d'évolution par rapport au même mois de l'année précédente 
-- Pour calculer le taux d'évolution on a utilise cette formule = (valeur_année_actuelle - valeur_année_précédente) * 100 / valeur_année_précédente 
   
/*
La fonction LAG() permet de récupérer la valeur de la ligne précédente. Dans notre cas, on a utilise pour obtenir
 le total des produits vendus de l'année précédente, en partitionnant par catégorie et mois (PARTITION BY category, month_ordre), 
 et en triant chronologiquement par année (ORDER BY year_ordre). 
 */
 
-- Définition d'une table temporaire avec les ventes mensuelles : sales_product_per_month 
WITH sales_product_per_month AS (select MONTH(orders.orderDate) as month_ordre ,YEAR(orders.orderDate) as year_ordre,products.productLine as category,
sum(orderdetails.quantityOrdered) as total_product_sales ,
sum(orderdetails.quantityOrdered * orderdetails.priceEach) as total_revenue,
sum(orderdetails.quantityOrdered * products.buyPrice) as total_cost -- Coût total des produits
from orderdetails
join orders
on orders.orderNumber = orderdetails.orderNumber
join products
on products.productCode = orderdetails.productCode
group by YEAR(orders.orderDate), MONTH(orders.orderDate), products.productLine)

select year_ordre, month_ordre, category, total_product_sales, total_revenue, total_cost, total_revenue - total_cost as gross_margin,
COALESCE(SUM(total_product_sales) OVER (PARTITION BY category, year_ordre ORDER BY month_ordre), 0) AS cumulative_sales, -- Cumulative sales pour chaque année
COALESCE(LAG(total_product_sales) OVER (PARTITION BY category, month_ordre ORDER BY year_ordre), 0) AS total_product_sales_previous_year, -- Total de produits vendus de l'année précédente 
COALESCE(ROUND(((total_product_sales - LAG(total_product_sales) OVER (PARTITION BY category, month_ordre ORDER BY year_ordre)) * 100.0 / 
LAG(total_product_sales) OVER (PARTITION BY category, month_ordre ORDER BY year_ordre)), 2), 0) AS SalesGrowth -- Taux d'evolution des ventes (%)
from sales_product_per_month;


-- Question : - Le chiffre d'affaires des commandes des deux derniers mois de la base de données par pays.

/* Cette requête calcule le chiffre d'affaires des commandes sur deux mois consécutifs, groupé par pays. L'objectif est de permettre une analyse dynamique dans Power BI.
 Dans Power BI : 
 1. Un segment permet à l'utilisateur de sélectionner une année et un mois spécifiques.
 2. Une fois le mois sélectionné, on affiche :
   - Le chiffre d'affaires du mois sélectionné.
   - Le chiffre d'affaires du mois précédent. 

Cela fournit plus d'informations et une meilleure compréhension de la tendance des ventes. */

/* Structure du raisonement  :

with table1 as () , table2 as() 
select  colonnes 
from table1
left join table2  */

/* On a utilise deux tables temporaires :
Table1 : 'data_all_months' qui contient toutes les combinaisons possibles de pays , année et mois
Table2 : 'sales_data' qui contient le CA pour chaque combinaisons de pays, année et mois 
*/

/* on a utilise left join pour assure que toutes les données de référence (tous les mois pour chaque pays) sont présentes,
même si certains mois n'ont pas de chiffre d'affaires enregistré.*/

-- Table temporaire 1 pour avoir un table de reference qui contient tous les pays , années et mois 
with data_all_months as (select c.country, y.year_ordre as year, m.month_order as month
    from 
        (select DISTINCT country from customers) c -- Liste unique des pays
    CROSS JOIN 
        (select DISTINCT YEAR(orderDate) AS year_ordre from orders) y -- Liste unique des années
    CROSS JOIN 
         (select DISTINCT MONTH(orderDate) AS month_order from orders) m), -- Liste unique des mois
         
 -- Table Temporaire 2 pour calculer le CA par pays, année et mois         
sales_data as ( select customers.country,YEAR(orders.orderDate) as year,MONTH(orders.orderDate) as month,SUM(orderdetails.quantityOrdered * orderdetails.priceEach) as CA
    from customers
    join orders on customers.customerNumber = orders.customerNumber
    join  orderdetails on orderdetails.orderNumber = orders.orderNumber
	where orders.status not in ('On Hold', 'Cancelled') -- Filtre les commandes 'On Hold' et 'Cancelled'
    group by customers.country, YEAR(orders.orderDate), MONTH(orders.orderDate))

select dm.country,dm.year,dm.month,
COALESCE(sales_data.CA, 0) AS CA, -- Remplace NULL par 0
LAG(COALESCE(sales_data.CA, 0)) over (PARTITION BY dm.country order by dm.year, dm.month) as CA_previous_month -- CA du mois précédent dans le meme pays ( partitionné par 'country') et tiré par année et mois
from data_all_months dm
left join sales_data  on dm.country = sales_data.country and dm.year = sales_data.year and dm.month = sales_data.month
ORDER BY dm.country, dm.year, dm.month;
/* Alors  left join pour avoir toutes les mois de la table data_all_months
meme si elles n'ont pas de correspondance ( pas de CA) dans la table sales_data cela garantit que les mois sans CA apparait avec un CA = 0 */

-- et si l'objectif est de récupérer uniquement les commandes des deux derniers mois, on applique cette condition :
WHERE orders.orderDate BETWEEN 
      DATE_SUB((SELECT MAX(orderDate) FROM orders), INTERVAL 2 MONTH) -- Deux mois avant la date la plus récente
      AND (SELECT MAX(orderDate) FROM orders) -- Date de la commande la plus récente. 
      

-- Questions = Commandes qui n'ont pas encore été payées.

-- Etape 1 : Identifier les types de statuts disponibles dans la table 'orders'
select status,count(*) as total_orders -- Nombre total de commandes par statut
 from orders
 group by status ;
 
-- Etape 2 : Identifier les commandes 'On Hold' ou annulées, ainsi que les clients associés
select 
customers.customerNumber, -- Identifiant unique du client 
customers.customerName, -- Nom du client
orders.orderNumber, --  Numéro de la commande
CONCAT(customers.contactLastName, ' ',customers.contactFirstName ) as contact_name,
CONCAT(employees.firstName, ' ', employees.lastName) AS employee_name , -- Nom de l'employée refrent au client
sum(orderdetails.quantityOrdered*orderdetails.priceEach) as amount_ordered,-- Montant total de la commande
orders.status -- Statut de la commande
from orders
join orderdetails 
on orderdetails.orderNumber = orders.orderNumber 
join customers 
on customers.customerNumber=orders.customerNumber
join employees on customers.salesRepEmployeeNumber = employees.employeeNumber
where orders.status in ('On Hold','Cancelled') -- Afficher les commandes avec un statut 'On Hold'  et 'Cancelled'
group by customers.customerNumber,orders.orderNumber,employees.firstName, employees.lastName ;-- Regroupe par client, commande et emplpoye

--  Etape 3 :  Identifier clients qui n'ont pas encore terminer leur paiment et lier chaque client à son employé refernt
 /* 
 Problématique : Table 'orders' et 'payments' ne sont pas directement liées, ce qui nécessite un rattachement via la table 'customers'.
 pour calculer les montants des commandés, payés et impayés par client. 
 
 But : Calculer pour chaque client :
- amount_ordered : Montant total des commandes passées.
- amount_paid : Montant total des paiements effectués.
 La différence entre ces deux montants (amount_ordered - amount_paid) donne les montant non payé par client
  Dans la requete suivante on regroupe les données par custumerNumber pour effectuer ces caluls 
 */
 
-- Etape 3.1 : Calculer les montants total des commandes par client 
SELECT 
c.customerNumber,
c.customerName AS nomclient,
c.salesRepEmployeeNumber AS employee , -- Employée responsable du client
SUM(od.quantityOrdered * od.priceEach) as amount_ordered
FROM orderdetails od
JOIN orders o ON od.orderNumber = o.orderNumber
JOIN customers c ON o.customerNumber = c.customerNumber
GROUP BY c.customerNumber, c.salesRepEmployeeNumber;

-- Etape 3.2 : Calculer les montants total des paiements effectués par chaque clients à l'aide de la table payments 
-- group by customers pour obtenir un total des paiements par client.
select c.customerNumber , coalesce(SUM(p.amount),0) as amount_paid 
from customers c 
join payments p on p.customerNumber = c.customerNumber
group by c.customerNumber;

 /* Exemple de structure du code  :
with table1 as () , table2 as() 
select 
from table1
join table2 
*/

with amount_orderd_per_client as (
select 
customers.customerNumber,
customers.customerName, -- Nom du client
CONCAT(customers.contactLastName, ' ',customers.contactFirstName ) as contact_name,
customers.salesRepEmployeeNumber as id_employee,
CONCAT(employees.firstName, ' ', employees.lastName) AS employee_name,
sum(orderdetails.quantityOrdered*orderdetails.priceEach) as amount_ordered-- Montant total de la commande
from orders
join orderdetails 
on orderdetails.orderNumber = orders.orderNumber 
join customers 
on customers.customerNumber=orders.customerNumber
join employees on customers.salesRepEmployeeNumber = employees.employeeNumber 
where orders.status not in ('Cancelled') -- filtre les commandes annulées
group by customers.customerNumber,customers.customerName, customers.salesRepEmployeeNumber,employees.firstName, employees.lastName) ,
amount_paid_per_client as (
select customers.customerNumber , coalesce(SUM(payments.amount),0) as amount_paid 
from customers 
join payments on payments.customerNumber = customers.customerNumber
group by customers.customerNumber )

-- Etape 3.3 : Combiner les montants commandés et payés, et calculer les montants impayés.
select oc.customerNumber ,oc.customerName ,oc.id_employee ,oc.employee_name, oc.amount_ordered , pc.amount_paid,
case 
	when (oc.amount_ordered - pc.amount_paid) < 0 then 0 -- Si les paiments depassée le montant du commandes, then le montant impayé = 0
	else (oc.amount_ordered - pc.amount_paid)  -- Else calculer la difference 
end as unpaid_amount
from amount_orderd_per_client oc 
join amount_paid_per_client pc on oc.customerNumber = pc.customerNumber -- Lier les commandes et paiments par client
order by unpaid_amount desc ;

-- Question : Identifier les 5 produits les plus commandés 

select * from products;
select 
products.productCode,
products.productName, --  Nom du produit
products.productVendor,
products.quantityInStock , -- Quantité en stock du produit
COALESCE(sum(orderdetails.quantityOrdered),0) as total_orders, -- Total des commandes pour ce produit
round(COALESCE(sum(orderdetails.quantityOrdered),0)/products.quantityInStock,2) as ratio_demande_Prodcut_stock, -- Ratio entre la demande (commandes) et le stock disponible
 MAX(orders.orderDate) AS last_order_date -- Dernière date de commande (NULL si aucune commande)
 from products 
 left join orderdetails 
 on products.productCode=orderdetails.productCode
 left join orders 
 on orders.orderNumber = orderdetails.orderNumber
 group by products.productCode
 order by total_orders DESC -- Trier par l'ordre decroissant du total des commandes 
  -- limit 5 ;   -- Limiter les resulats aux 5 produits les plus commandés
  
   /* Interprétation du ratio :
   - Ratio proche de 0 : Beaucoup de stock disponible, mais peu de commandes pour ce produit.
   - Ratio égal à 1 : Équilibre entre la demande (commandes) et le stock disponible.
   - Ratio supérieur à 1 : Produit très demandé avec un stock insuffisant. Cela peut indiquer un risque de rupture de stock.
*/     

-- Question : Ressources humaines: Chaque mois, les 2 vendeurs avec le CA le plus élevé.

-- Etape 1 : Vérifier les types d'emplois disponibles */
select  jobTitle , -- Type de poste
count(*) -- Nombre d'employés pour chaque type de poste
from employees
group by jobTitle;
-- on s'intresse uniquement sur les 'Sales Representatives' : 'Sales Rep'.

-- indice  : Utiliser la fonction RANK() pour identifier les deux meilleurs vendeurs de chaque mois

-- Etape 2 : Calculer les ventes mensuelles par employé avec classement 
-- Définition d'une table temporaire avec les ventes selon les employes : sales_per_employee
--  Récupérer le manager (m.lastName, m.firstName) de chaque employé (e.lastName, e.firstName)
WITH sales_per_employee as
 (
    select e.employeeNumber, -- employé
    CONCAT(e.firstName, ' ', e.lastName) as employee_name,
    e.reportsTo as id_manager, -- manager
    CONCAT(m.firstName, ' ', m.lastName) as manager_name,
	YEAR(orders.orderDate) as year,
    MONTH(orders.orderDate) as month,
    COALESCE(count(orders.orderNumber),0) as total_cmd, -- Total des commandes par employé
    COALESCE(sum(orderdetails.quantityOrdered * orderdetails.priceEach),0) as MonthlySales, -- Chiffre d'affaires mensuel
	RANK() OVER (PARTITION BY YEAR(orders.orderDate) ,MONTH(orders.orderDate)  Order by sum(orderdetails.quantityOrdered * orderdetails.priceEach) DESC ) as Ranking
   /* RANK() OVER() :
	  Classer les employés dans chaque mois et année (PARTITION BY year, month).
      Classement basé sur le chiffre d'affaires décroissant (ORDER BY MonthlySales DESC) */
    from employees e
    left join employees m  -- Auto-jointure pour récupérer le name de manager
    on e.reportsTo= m.employeeNumber -- Reliez chaque employé à son manager
    left join customers on e.employeeNumber = customers.salesRepEmployeeNumber
    left join orders on customers.customerNumber = orders.customerNumber
    left join orderdetails on orders.orderNumber = orderdetails.orderNumber
    where e.jobTitle = 'Sales Rep'
    GROUP BY e.employeeNumber,e.reportsTo, year, month) -- Regroupement par employé , manager, année, et mois

-- Étape 3 : Pas de filtre de ranking appliquer pour une vision plus élargie.
-- Mais si l'objectif est d'afficher uniquement les 2 meilleurs vendeurs par mois on applique la condition WHERE Ranking <= 2.
SELECT * from sales_per_employee
/*where Ranking <= 2 -- filtre les employés ayant un classement (ranking) inférieur ou égal à 2.*/
ORDER BY year DESC, month DESC ,ranking ;