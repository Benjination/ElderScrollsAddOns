# ElderScrollsAddOns

A collection of Elder Scrolls Online addons.

## Megastore - ESO Guild Store Scanner

An Elder Scrolls Online addon that scans and aggregates guild store data to help players find items across multiple guild traders.

### Features

- **Automatic Scanning**: Automatically scans guild stores when you browse them
- **Interactive Popup**: In-game popup with Manual Scan, Force Scan, Test, and Disable buttons
- **Search & Filter**: Search for items by name and filter by category (weapons, apparel, consumables, etc.)
- **Multi-Guild Support**: Aggregates data from multiple guild stores
- **Real-time Updates**: Shows live scanning progress and item counts
- **Data Persistence**: Saves scanned data between game sessions

### Installation

1. Download or clone this repository
2. Copy the `Megastore` folder to your ESO AddOns directory:
   - Windows: `Documents/Elder Scrolls Online/live/AddOns/`
   - Mac: `Documents/Elder Scrolls Online/live/AddOns/`
3. Enable the addon in-game through the Add-ons menu

### Usage

#### Automatic Scanning
- When you open a guild store and browse the items, Megastore will automatically start scanning
- A popup window will appear showing the scanning progress
- The popup stays visible and shows real-time updates during scanning

#### Manual Controls
Use the popup buttons for manual control:
- **Manual**: Trigger a manual scan of currently visible items
- **Force**: Force a search and scan even if no items are initially visible
- **Test**: Run diagnostic tests to check API functionality
- **Disable**: Disable auto-scanning (can be re-enabled with `/megastore debug`)

#### Chat Commands
- `/megastore` or `/mega` - Show help and current status
- `/megastore debug` - Enable debug mode and auto-scanning
- `/megastore scan` - Manually trigger a scan (when at a trading house)
- `/megastore test` - Run diagnostic tests
- `/megastore ui` - Open the main Megastore search interface

#### Search Interface
- Open with `/megastore ui` or through the main UI
- Search by item name
- Filter by categories: Weapons, Apparel, Jewelry, Consumables, Materials, Glyphs, Furnishings, Misc
- View results with price, seller, location, and age information

### Technical Notes

#### API Usage
This addon uses ESO's Trading House APIs correctly:
- **Browse Tab**: Uses `GetTradingHouseSearchResultNumItems()` and `GetTradingHouseSearchResultItemInfo()` to scan items available for purchase
- **Listings Tab**: Would use `GetTradingHouseNumItems()` and `GetTradingHouseListingItemInfo()` for your own listings

#### Data Storage
- Item data is stored in saved variables and persists between sessions
- Old data is automatically cleaned up based on age settings
- Data includes item name, price, seller, guild, location, and timestamp

### Troubleshooting

#### Scanner Shows "0 Items Found"
This was a common issue that has been fixed. The addon now correctly scans the Browse tab instead of the Listings tab.

#### Popup Not Appearing
- Make sure you're at a guild trader and have opened the trading house interface
- Check that auto-scanning is enabled with `/megastore debug`
- The popup appears automatically when scanning starts

#### No Items in Search Results
- Make sure you've scanned some guild stores first
- Check that your search terms are correct
- Try the "All Items" view to see all scanned data

### Version History

#### v1.0.0
- Initial release with automatic scanning
- Interactive popup interface
- Search and filtering system
- Fixed Browse tab vs Listings tab API usage
- Added comprehensive debugging and testing tools

## Contributing

Feel free to submit issues and pull requests to improve the addons.

## License

These addons are provided as-is for the Elder Scrolls Online community.
