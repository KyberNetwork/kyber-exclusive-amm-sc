import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
from sklearn.linear_model import LinearRegression
from sklearn.metrics import r2_score, mean_squared_error
import seaborn as sns

# Set style for better plots
plt.style.use("default")
sns.set_palette("husl")


def analyze_swap_data(file_path, remove_outliers=True):
    """
    Read CSV file, perform linear regression, and visualize results
    """

    # Read the CSV file
    print("Reading data from:", file_path)
    try:
        # Read CSV without headers since the file doesn't have column names
        data = pd.read_csv(file_path, header=None, names=["X", "Y"])
        print(f"Successfully loaded {len(data)} data points")
        print("\nData summary:")
        print(data.describe())

    except FileNotFoundError:
        print(f"Error: File {file_path} not found")
        return
    except Exception as e:
        print(f"Error reading file: {e}")
        return

    # Function to find outliers using IQR method
    def find_outliers_mask(values):
        Q1 = values.quantile(0.25)
        Q3 = values.quantile(0.75)
        IQR = Q3 - Q1
        lower_bound = Q1 - 1.5 * IQR
        upper_bound = Q3 + 1.5 * IQR
        return (values < lower_bound) | (values > upper_bound)

    # Store original data
    original_data = data.copy()

    if remove_outliers:
        # Find outliers in both X and Y
        x_outliers_mask = find_outliers_mask(data["X"])
        y_outliers_mask = find_outliers_mask(data["Y"])

        # Combine outlier masks (remove points that are outliers in either X or Y)
        outliers_mask = x_outliers_mask | y_outliers_mask

        print(f"\n=== Outlier Removal ===")
        print(f"Original data points: {len(data)}")
        print(
            f"Outliers in X: {x_outliers_mask.sum()} ({x_outliers_mask.sum()/len(data)*100:.1f}%)"
        )
        print(
            f"Outliers in Y: {y_outliers_mask.sum()} ({y_outliers_mask.sum()/len(data)*100:.1f}%)"
        )
        print(
            f"Total outliers removed: {outliers_mask.sum()} ({outliers_mask.sum()/len(data)*100:.1f}%)"
        )

        # Filter out outliers
        data = data[~outliers_mask].copy()
        print(f"Remaining data points: {len(data)}")

        print("\nFiltered data summary:")
        print(data.describe())

    # Prepare data for linear regression
    X = data["X"].values.reshape(-1, 1)  # Reshape for sklearn
    y = data["Y"].values

    # Perform linear regression
    model = LinearRegression()
    model.fit(X, y)

    # Make predictions
    y_pred = model.predict(X)

    # Calculate metrics
    r2 = r2_score(y, y_pred)
    mse = mean_squared_error(y, y_pred)
    rmse = np.sqrt(mse)

    # Print regression results
    print(f"\n=== Linear Regression Results ===")
    print(f"Slope (coefficient): {model.coef_[0]:.6f}")
    print(f"Intercept: {model.intercept_:.6f}")
    print(f"R² Score: {r2:.6f}")
    print(f"Mean Squared Error: {mse:.2f}")
    print(f"Root Mean Squared Error: {rmse:.2f}")
    print(f"Equation: Y = {model.coef_[0]:.6f} * X + {model.intercept_:.6f}")

    # Create visualization
    plt.figure(figsize=(10, 8))

    # Scatter plot with regression line
    plt.scatter(
        data["X"],
        data["Y"],
        alpha=0.6,
        color="blue",
        s=30,
        label=f"Data points ({len(data)})",
    )
    plt.plot(
        data["X"],
        y_pred,
        color="darkred",
        linewidth=2,
        label=f"Linear fit (R² = {r2:.4f})",
    )
    plt.xlabel("X Values")
    plt.ylabel("Y Values")
    plt.title("Linear Regression: Swap without hook vs. with fair flow hook")
    plt.legend()
    plt.grid(True, alpha=0.3)

    # Add regression equation as text on the plot
    if model.intercept_ >= 0:
        equation_text = f"Y = {model.coef_[0]:.6f}X + {model.intercept_:.6f}"
    else:
        equation_text = f"Y = {model.coef_[0]:.6f}X - {abs(model.intercept_):.6f}"
    plt.text(
        0.05,
        0.95,
        equation_text,
        transform=plt.gca().transAxes,
        fontsize=12,
        bbox=dict(boxstyle="round,pad=0.3", facecolor="white", alpha=0.8),
    )

    plt.tight_layout()
    plt.show()

    # Additional analysis
    print(f"\n=== Additional Statistics ===")
    print(f"Correlation coefficient: {np.corrcoef(data['X'], data['Y'])[0,1]:.6f}")
    print(f"Data range - X: [{data['X'].min():.0f}, {data['X'].max():.0f}]")
    print(f"Data range - Y: [{data['Y'].min():.0f}, {data['Y'].max():.0f}]")

    return model, data, r2


if __name__ == "__main__":
    # Analyze the swap data with outliers removed for cleaner visualization
    file_path = "snapshots/uniswap/swapWithBothPools.csv"
    model, data, r2_score = analyze_swap_data(file_path, remove_outliers=False)
