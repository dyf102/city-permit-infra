import { test, expect } from '@playwright/test';

test.describe('Production Verification', () => {
  test('verify /track page loads and interacts', async ({ page }) => {
    // Navigate to /track
    await page.goto('/track');

    // Verify it loads - check for "Property Details" heading
    await expect(page.getByRole('heading', { name: 'Property Details', level: 2 })).toBeVisible({ timeout: 15000 });

    // Perform a basic interaction: typing an address
    const addressInput = page.locator('#address-input');
    await addressInput.fill('100 Queen St W, Toronto');
    
    // Check if next button is visible
    await expect(page.locator('#next-step-btn')).toBeVisible();
  });

  test('verify /explore page loads and interacts', async ({ page }) => {
    // Navigate to /explore
    await page.goto('/explore');

    // Verify it loads - check for "Zoning Verdict" or search input
    await expect(page.getByPlaceholder('Search any Toronto address...')).toBeVisible({ timeout: 15000 });

    // Perform a basic interaction
    const searchInput = page.getByPlaceholder('Search any Toronto address...');
    await searchInput.fill('100 Queen St W');
    
    // Check for buildability button
    await expect(page.getByRole('button', { name: 'Check Buildability' })).toBeVisible();
  });
});
