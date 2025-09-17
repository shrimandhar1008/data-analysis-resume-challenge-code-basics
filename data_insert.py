from sqlalchemy import create_engine
import pandas as pd
import os
import sys
from pandas.tseries.offsets import MonthEnd

class Media:
    def __init__(self):
        self.engine = create_engine("mysql+pymysql://root:Shri%400177@localhost:3306/media_publishing")

    def __del__(self):
        del self.engine

    @staticmethod
    def process_quarter(val):
        if 'Q1' in val:
            return 'June'
        elif 'Q2' in val:
            return 'September'
        elif 'Q3' in val:
            return 'December'
        elif '4th Qtr' or 'Q4':
            return 'March'

    def process_data(self,*paths):
        for path in paths:
            try:
                file_name = os.path.splitext(os.path.basename(path))[0]
                df = pd.read_csv(path)
                if file_name == 'fact_ad_revenue':
                    df['year'] = df['quarter'].apply(lambda x: ''.join(y if y.isdigit() else '' for y in x.split('-')))
                    df['year1'] = df['quarter'].apply(lambda x: ''.join(y if y.isdigit() else '' for y in x.split(' ')))
                    df['year'] = df['year'] + df['year1']
                    del df['year1']
                    df['qtr'] = df['quarter'].apply(Media.process_quarter)
                    df['quarter'] = pd.to_datetime(df['qtr'] + df['year']) + MonthEnd(0)
                    df['currency'] = df['currency'].apply(lambda x: x.replace('IN RUPEES', 'INR'))
                    df['ad_revenue'] = df.apply(lambda row: row['ad_revenue'] * 88.15 if row['currency'] == 'USD' else (
                        row['ad_revenue'] * 103.04 if row['currency'] == 'EUR' else row['ad_revenue'] * 1), axis=1)
                    df['currency'] = 'INR'
                    df.sort_values(by='quarter', inplace=True)
                    df.drop(columns=['year', 'qtr'], inplace=True)
                    df.reset_index(drop=True, inplace=True)
                elif file_name == 'fact_city_readiness':
                    df['year'] = df['quarter'].apply(lambda x: ''.join(y if y.isdigit() else '' for y in x.split('-')))
                    df['qtr'] = df['quarter'].apply(Media.process_quarter)
                    df['quarter'] = pd.to_datetime(df['qtr'] + df['year']) + MonthEnd(0)
                    df.sort_values(by='quarter', inplace=True)
                    df.drop(columns=['Unnamed: 0', 'year', 'qtr'], inplace=True)
                elif file_name == 'fact_digital_pilot':
                    df['launch_month'] = pd.to_datetime(df['launch_month']) + MonthEnd(0)
                    df.drop(columns=['Unnamed: 0'], inplace=True)
                elif file_name == 'fact_print_sales':
                    df.columns = ['_'.join(i.split(' ')) for i in df.columns]
                    df['Copies_Sold'] = df['Copies_Sold'].apply(lambda x: x.replace('â‚¹', ''))
                    df['Copies_Sold'] = df['Copies_Sold'].astype(int)
                    df["normalized_date"] = pd.to_datetime(
                        df["Month"],
                        format="%b-%y",  # Try month-year format
                        errors="coerce"  # If fails, leave as NaT
                    )
                    df["Language"] = df["Language"].apply(lambda x:x.lower())
                    df["State"] = df["State"].apply(lambda x:x.lower())
                    df["State"] = df["State"].apply(lambda x:' '.join(x.split('-')))
                    df["State"] = df["State"].apply(lambda x:' '.join(x.split('_')))
                    # Fill remaining NaT by trying alternative format (YYYY/MM)
                    mask = df["normalized_date"].isna()
                    df.loc[mask, "normalized_date"] = pd.to_datetime(
                        df.loc[mask, "Month"],
                        format="%Y/%m",
                        errors="coerce"
                    )
                    df['Month'] = df["normalized_date"] + MonthEnd(0)
                    df.drop(columns=['normalized_date'], inplace=True)
                else:
                    pass

                # Write to MySQL
                df.to_sql(os.path.splitext(os.path.basename(path))[0], con=self.engine, if_exists="replace", index=False)
            except Exception as e:
                print(e, sys.exc_info()[-1].tb_lineno)



if __name__ == "__main__":
    obj = Media()
    obj.process_data(
        r"E:\Shrimandhar\Data_Analysis\rpc_17_inputs\rpc_17_inputs\Datasets\fact_print_sales.csv"
    )
