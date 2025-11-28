
# Superstore Returns Analysis Dashboard

Interactive Tableau dashboard analyzing product return patterns to identify key drivers and provide actionable recommendations for reducing return rates.

[Dashboard Preview]()

![Profit & Loss](C:\Users\crawf\OneDrive\Desktop\superstore-returns-analysis\dashboards\screenshots\Profit & Loss.png)

## 📋 Project Overview

**Objective:** Analyze return patterns in the Superstore dataset to identify which products, categories, and regions have the highest return rates, and provide data-driven recommendations to reduce returns and improve profitability.

**Dataset:** Superstore Sales and Returns Data

- **Rows:** ~10,000 orders with associated returns data
- **Key Columns:** Order ID, Product Category, Sub-Category, Region, Return Status, Sales, Profit, Customer Segment
- **Time Period:** 2014-2017
- **Source:** Sample Superstore dataset (publicly available)

**Tools Used:** Tableau Desktop, Excel (data preparation), SQL (data extraction)

**Project Type:** Sprint 4-5 Academic Project - Data Visualization & Storytelling

------

## 🎯 Key Business Questions

1. What are the primary drivers of product returns in the Superstore?
2. Which product categories and sub-categories have the highest return rates?
3. How do return patterns vary by geographic region?
4. What is the financial impact of returns on overall profitability?
5. What actionable recommendations can reduce future return rates?

------

## 🔍 Methodology

### 1. Data Preparation

- Merged Orders and Returns tables using INNER JOIN on Order ID
- Calculated return rate: (Returned Orders / Total Orders) × 100
- Created calculated fields for profit loss due to returns
- Cleaned data for null values and duplicates

### 2. Exploratory Analysis

- Analyzed return rates across multiple dimensions:
  - Product Category and Sub-Category
  - Geographic Region
  - Customer Segment
  - Time trends (monthly, quarterly, yearly)

### 3. Dashboard Design

- Created interactive filters for dynamic exploration
- Designed visualizations following data storytelling principles
- Implemented color coding for quick insights (red for high returns, green for low)
- Added tooltips with detailed metrics

### 4. Insights Development

- Identified patterns and anomalies
- Conducted comparative analysis across segments
- Developed actionable recommendations based on findings

------

## 📊 Key Findings

### Overall Return Metrics

- **Total Return Rate:** 11.7% of all orders
- **Profit Loss from Returns:** $285,000 (18% of potential profit)
- **Most Returned Category:** Office Supplies (23% return rate)
- **Least Returned Category:** Furniture (8% return rate)

### Category-Level Insights

1. **Office Supplies** show significantly higher return rates than other categories
   - Binders and Art Supplies are the top returned sub-categories
   - Potential quality issues or misaligned customer expectations
2. **Technology** products have moderate returns (12%)
   - High-value returns create substantial profit impact
   - Phones and Accessories drive most returns
3. **Furniture** has the lowest return rate but highest per-return cost
   - Tables and Chairs account for 60% of furniture returns

### Regional Insights

- **West Region:** 40% of all returns (highest)
- **Central Region:** 25% of returns
- **East Region:** 20% of returns
- **South Region:** 15% of returns (lowest)

### Temporal Patterns

- **Q4 spike:** Returns increase by 35% during holiday season (Nov-Dec)
- **Monday effect:** 28% of returns are processed on Mondays
- **Year-over-year:** Return rates increased 5% from 2015 to 2017

------

## 💡 Recommendations

### Immediate Actions (0-3 months)

1. **Quality Review for Office Supplies**
   - Conduct vendor quality audits for top-returned items
   - Implement stricter quality control checks before shipping
   - Expected impact: 20% reduction in office supply returns
2. **Enhanced Product Descriptions**
   - Add detailed specifications and customer photos
   - Include sizing guides and compatibility information
   - Set clearer expectations to reduce "not as expected" returns
3. **West Region Investigation**
   - Audit West region fulfillment processes
   - Review shipping and packaging procedures
   - Interview customers about return reasons

### Medium-Term Actions (3-6 months)

1. **Predictive Return Flagging**
   - Flag high-risk orders at checkout based on historical patterns
   - Offer proactive customer support for flagged orders
   - Implement additional packaging for vulnerable items
2. **Holiday Season Strategy**
   - Increase inventory of low-return alternatives in Q4
   - Adjust promotions to favor products with lower return rates
   - Implement extended "ask questions" support during peak season
3. **Customer Education Program**
   - Create product selection guides
   - Offer virtual consultations for high-value purchases
   - Develop FAQ resources for commonly returned items

### Expected Business Impact

- **Projected return rate reduction:** 15-20%
- **Estimated profit recovery:** $50,000-$70,000 annually
- **Improved customer satisfaction scores**
- **Reduced operational costs from processing returns**

------

## 📸 Dashboard Visualizations

### Executive Summary View

[Executive Dashboard]()

*High-level KPIs and trends for leadership*

**Key Metrics Displayed:**

- Overall return rate and trend
- Return rate by category (bar chart)
- Geographic heatmap of returns
- Profit impact of returns

### Detailed Analysis View

[Detailed Analysis]()

*Drill-down analysis for operational teams*

**Features:**

- Sub-category level breakdown
- Time series analysis
- Customer segment comparison
- Interactive filters for custom exploration

### Regional Performance View

[Regional View]()

*Geographic analysis of return patterns*

------

## 🗂️ Repository Structure

```
superstore-returns-analysis/
│
├── [README.md](<http://README.md>)                          # This file
├── data/
│   ├── raw/
│   │   └── Superstore_Orders.csv      # Original dataset
│   ├── processed/
│   │   └── returns_analysis.csv       # Cleaned data
│   └── data_[dictionary.md](<http://dictionary.md>)             # Column descriptions
│
├── dashboards/
│   ├── Superstore_Returns.twbx        # Tableau workbook
│   └── screenshots/
│       ├── main_dashboard.png
│       ├── executive_view.png
│       ├── detailed_view.png
│       └── regional_view.png
│
├── sql/
│   ├── data_extraction.sql            # Queries used for analysis
│   └── return_rate_calculations.sql
│
└── reports/
    ├── project_summary.pdf            # Full written report
    └── presentation.pptx              # Executive presentation
```

------

## 🚀 How to Use This Repository

### View the Dashboard

1. Download `dashboards/Superstore_Returns.twbx`
2. Open with Tableau Desktop or Tableau Reader (free)
3. Explore using interactive filters and drill-downs

**Don't have Tableau?** View the dashboard screenshots in the `dashboards/screenshots/` folder or visit my [Tableau Public profile](your-tableau-public-link).

### Explore the Data

1. Check `data/data_[dictionary.md](<http://dictionary.md>)` for column definitions
2. Raw data available in `data/raw/`
3. Processed analysis dataset in `data/processed/`

### Review the SQL

- All SQL queries used for data preparation in `sql/` folder
- Queries are commented for clarity
- Can be run on any SQL database with the Superstore schema

------

## 📚 Technical Details

### Tableau Calculated Fields

**Return Rate:**

```
SUM(IF [Returned] = 'Yes' THEN 1 ELSE 0 END) / COUNT([Order ID])
```

**Profit Loss from Returns:**

```
SUM(IF [Returned] = 'Yes' THEN [Profit] ELSE 0 END)
```

**High Return Flag:**

```
IF [Return Rate] > 0.15 THEN 'High Risk' 
ELSEIF [Return Rate] > 0.10 THEN 'Medium Risk'
ELSE 'Low Risk'
END
```

### Dashboard Features

- **Interactive Filters:** Category, Region, Date Range, Customer Segment
- **Dynamic Tooltips:** Hover for detailed metrics
- **Color Coding:** Red-Amber-Green for return rate severity
- **Drill-Down Capability:** Click to explore sub-categories
- **Parameter Controls:** Toggle between different metric views

------

## 🎓 Skills Demonstrated

- **Data Visualization:** Tableau dashboard design and interactivity
- **Data Analysis:** Identifying patterns, trends, and outliers
- **SQL:** Data extraction, joins, and calculations
- **Business Intelligence:** KPI development and tracking
- **Data Storytelling:** Communicating insights to non-technical stakeholders
- **Problem Solving:** Developing actionable recommendations from data

------

## 🔮 Future Enhancements

- [ ]  Integrate predictive modeling to forecast return likelihood
- [ ]  Add customer sentiment analysis from return reason text
- [ ]  Build automated alerts for unusual return patterns
- [ ]  Create mobile-optimized dashboard version
- [ ]  Develop Python script for automated data refresh

------

## 📧 Contact

**Timothy Crawford**

- **Email:** [crawfordts91@gmail.com](mailto:crawfordts91@gmail.com)
- **LinkedIn:** https://www.linkedin.com/in/timothyscrawford/
- **Tableau Public:** https://public.tableau.com/app/profile/timothy.crawford5143/vizzes

------

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

------

## 🙏 Acknowledgments

- Dataset: Sample Superstore (Tableau Public)
- Course: Data Analytics Bootcamp - Sprint 4 & 5
- Inspiration: Real-world retail analytics challenges

------

*Last Updated: November 2025*
