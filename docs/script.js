// Web Monitor Dashboard Script
class WebMonitorDashboard {
    constructor() {
        this.statusData = null;
        this.historyData = null;
        this.init();
    }

    async init() {
        try {
            await this.loadData();
            this.renderDashboard();
            this.hideLoading();
        } catch (error) {
            console.error('Failed to load data:', error);
            this.showError(error.message);
        }
    }

    async loadData() {
        try {
            // Load status and history data in parallel
            const [statusResponse, historyResponse] = await Promise.all([
                fetch('./data/status.json'),
                fetch('./data/history.json')
            ]);

            if (!statusResponse.ok) {
                throw new Error(`Status data load failed: ${statusResponse.status}`);
            }

            if (!historyResponse.ok) {
                throw new Error(`History data load failed: ${historyResponse.status}`);
            }

            this.statusData = await statusResponse.json();
            this.historyData = await historyResponse.json();
        } catch (error) {
            throw new Error(`データの読み込みに失敗しました: ${error.message}`);
        }
    }

    renderDashboard() {
        this.renderLastUpdated();
        this.renderSites();
        this.renderHistory();
    }

    renderLastUpdated() {
        const lastUpdatedElement = document.getElementById('lastUpdated');
        if (this.statusData?.last_updated) {
            const date = new Date(this.statusData.last_updated);
            const formattedDate = date.toLocaleString('ja-JP', {
                year: 'numeric',
                month: '2-digit',
                day: '2-digit',
                hour: '2-digit',
                minute: '2-digit'
            });
            lastUpdatedElement.textContent = `最終コンテンツ更新: ${formattedDate}`;
        } else {
            lastUpdatedElement.textContent = '最終コンテンツ更新: まだ更新なし';
        }
    }

    renderSites() {
        const sitesGrid = document.getElementById('sitesGrid');
        
        if (!this.statusData?.sites || this.statusData.sites.length === 0) {
            sitesGrid.innerHTML = '<p class="no-data">監視対象サイトがありません</p>';
            return;
        }

        sitesGrid.innerHTML = this.statusData.sites.map(site => this.createSiteCard(site)).join('');
    }

    createSiteCard(site) {
        const statusIcon = this.getStatusIcon(site.status);
        const statusClass = this.getStatusClass(site.status);
        const lastCheck = site.last_check ? new Date(site.last_check).toLocaleString('ja-JP') : 'なし';
        const lastChange = site.last_change ? new Date(site.last_change).toLocaleString('ja-JP') : 'なし';

        return `
            <div class="site-card">
                <div class="site-header">
                    <div class="site-name">${this.escapeHtml(site.name)}</div>
                    <div class="site-status ${statusClass}">
                        ${statusIcon} ${this.getStatusText(site.status)}
                    </div>
                </div>
                <div class="site-url">
                    <a href="${this.escapeHtml(site.url)}" target="_blank" rel="noopener">
                        ${this.escapeHtml(site.url)}
                    </a>
                </div>
                <div class="site-meta">
                    <div class="site-meta-item">
                        <span>最終チェック:</span>
                        <span>${lastCheck}</span>
                    </div>
                    <div class="site-meta-item">
                        <span>最終変更:</span>
                        <span>${lastChange}</span>
                    </div>
                    ${site.error ? `
                        <div class="site-meta-item error">
                            <span>エラー:</span>
                            <span>${this.escapeHtml(site.error)}</span>
                        </div>
                    ` : ''}
                </div>
            </div>
        `;
    }

    renderHistory() {
        const historyList = document.getElementById('historyList');
        const allHistory = this.getAllHistoryItems();
        
        if (allHistory.length === 0) {
            historyList.innerHTML = '<div class="history-item"><p>履歴データがありません</p></div>';
            return;
        }

        // Sort by timestamp (newest first) and take last 20 items
        const recentHistory = allHistory.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp)).slice(0, 20);
        
        historyList.innerHTML = recentHistory.map(item => this.createHistoryItem(item)).join('');
    }

    getAllHistoryItems() {
        const allItems = [];
        
        if (!this.historyData) return allItems;
        
        // Get site names from status data for reference
        const siteNames = {};
        if (this.statusData?.sites) {
            this.statusData.sites.forEach(site => {
                siteNames[site.id] = site.name;
            });
        }

        Object.entries(this.historyData).forEach(([siteId, history]) => {
            const siteName = siteNames[siteId] || siteId;
            history.forEach(item => {
                allItems.push({
                    ...item,
                    siteId,
                    siteName
                });
            });
        });

        return allItems;
    }

    createHistoryItem(item) {
        const statusClass = item.status;
        const time = new Date(item.timestamp).toLocaleString('ja-JP');
        const message = this.getHistoryMessage(item.status, item.change_detected);

        return `
            <div class="history-item">
                <div class="history-info">
                    <div class="history-status ${statusClass}"></div>
                    <div class="history-text">
                        <div class="history-site">${this.escapeHtml(item.siteName)}</div>
                        <div class="history-message">${message}</div>
                    </div>
                </div>
                <div class="history-time">${time}</div>
            </div>
        `;
    }

    getStatusIcon(status) {
        switch (status) {
            case 'unchanged': return '🟢';
            case 'updated': return '🟡';
            case 'error': return '🔴';
            default: return '⚪';
        }
    }

    getStatusClass(status) {
        return `status-${status}`;
    }

    getStatusText(status) {
        switch (status) {
            case 'unchanged': return '変更なし';
            case 'updated': return '更新検知';
            case 'error': return 'エラー';
            default: return '不明';
        }
    }

    getHistoryMessage(status, changeDetected) {
        if (status === 'error') return 'エラーが発生しました';
        if (changeDetected) return 'コンテンツの変更を検知しました';
        return 'チェック完了（変更なし）';
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }

    hideLoading() {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('content').style.display = 'block';
    }

    showError(message) {
        document.getElementById('loading').style.display = 'none';
        document.getElementById('error').style.display = 'block';
        document.getElementById('errorMessage').textContent = message;
    }
}

// Initialize dashboard when DOM is loaded
document.addEventListener('DOMContentLoaded', () => {
    new WebMonitorDashboard();
});

// Auto-refresh every 5 minutes
setInterval(() => {
    location.reload();
}, 5 * 60 * 1000);