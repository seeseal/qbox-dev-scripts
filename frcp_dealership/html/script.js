// ============================================
//  frcp_dealership | script.js  v2.0
//  Original catalog logic preserved.
//  Added: tab switching, employee panel,
//  boss panel, society fund UI, staff modals.
// ============================================

console.log('[FD] script.js v2.0 loading...');

// ── State ──────────────────────────────────

var catalog        = [];
var tickets        = { elite: 0, apex: 0 };
var balance        = 0;
var activeTier     = 'all';
var activeCategory = 'all';
var activeSort     = 'default';
var selectedVehicle = null;
var isEmployee     = false;
var isBoss         = false;
var societyBalance = 0;
var staffModalAction = null;  // 'hire' | 'fire' | 'promote' | 'demote'

// ── Tab Switching ──────────────────────────

function switchTab(tabName) {
    document.querySelectorAll('.tab-btn').forEach(function(btn) {
        btn.classList.toggle('active', btn.dataset.tab === tabName);
    });
    document.querySelectorAll('.tab-content').forEach(function(el) {
        el.classList.add('hidden');
        el.classList.remove('active');
    });
    var target = document.getElementById('tab-content-' + tabName);
    if (target) {
        target.classList.remove('hidden');
        target.classList.add('active');
    }
}

document.querySelectorAll('.tab-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        if (!btn.classList.contains('hidden')) {
            switchTab(btn.dataset.tab);
        }
    });
});

// ── NUI Message Handler ───────────────────

window.addEventListener('message', function(event) {
    var action = event.data.action;

    if (action === 'openDealership') {
        try {
            var data       = event.data.data;
            catalog        = data.catalog;
            tickets        = data.tickets;
            balance        = data.balance;
            isEmployee     = data.isEmployee || false;
            isBoss         = data.isBoss     || false;

            document.getElementById('dealership-name').textContent  = event.data.dealershipName;
            document.getElementById('player-name').textContent      = 'Welcome, ' + data.playerName;
            document.getElementById('player-balance').textContent   = '$' + balance.toLocaleString();
            document.getElementById('ticket-elite').textContent     = tickets.elite;
            document.getElementById('ticket-apex').textContent      = tickets.apex;

            // ── Assistant Banner ──────────────────────────────
            var assistantBanner   = document.getElementById('assistant-banner');
            var noEmployeeBanner  = document.getElementById('no-employee-banner');
            assistantBanner.classList.add('hidden');
            noEmployeeBanner.classList.add('hidden');

            if (!isEmployee) {
                // Customer view — show assistant info or warning
                if (data.assistant) {
                    document.getElementById('assistant-name').textContent  = data.assistant.name;
                    document.getElementById('assistant-grade').textContent = data.assistant.grade;
                    var commWrap = document.getElementById('assistant-commission-wrap');
                    if (data.assistant.commission > 0) {
                        document.getElementById('assistant-commission').textContent = data.assistant.commission;
                        commWrap.classList.remove('hidden');
                    } else {
                        commWrap.classList.add('hidden');
                    }
                    assistantBanner.classList.remove('hidden');
                } else {
                    noEmployeeBanner.classList.remove('hidden');
                }
            }
            // ─────────────────────────────────────────────────

            // Show employee badge + tabs
            var badge   = document.getElementById('employee-badge');
            var jobTab  = document.getElementById('tab-job');
            var bossTab = document.getElementById('tab-boss');

            if (isEmployee) {
                badge.classList.remove('hidden');
                document.getElementById('employee-grade-label').textContent = data.jobGrade || 'Employee';
                jobTab.classList.remove('hidden');
                document.getElementById('job-grade-display').textContent = data.jobGrade || '—';
            } else {
                badge.classList.add('hidden');
                jobTab.classList.add('hidden');
                bossTab.classList.add('hidden');
            }

            if (isBoss) {
                bossTab.classList.remove('hidden');
                document.getElementById('society-pct').textContent = '80%';
                document.getElementById('tax-pct').textContent     = '20%';
            } else {
                bossTab.classList.add('hidden');
            }

            buildCategoryFilters(event.data.categories);
            renderVehicles();
            document.getElementById('dealership-ui').classList.remove('hidden');
            switchTab('catalog');

        } catch(err) {
            console.error('[FD] ERROR in openDealership:', err.message, err.stack);
        }
    }

    if (action === 'closeUI') {
        closeUI();
    }

    if (action === 'updateSupply') {
        var updatedModel = event.data.model;
        var newSold      = event.data.sold;
        catalog.forEach(function(v) {
            if (v.model === updatedModel && v.limit !== -1) {
                v.remaining = v.limit - newSold;
                v.available = v.remaining > 0;
            }
        });
        renderVehicles();
    }

    if (action === 'receiveSocietyBalance') {
        societyBalance = event.data.balance || 0;
        document.getElementById('society-balance-display').textContent = '$' + societyBalance.toLocaleString();
        document.getElementById('withdraw-available').textContent = '$' + societyBalance.toLocaleString();
    }
});

// ── Category Filter Buttons ───────────────

function buildCategoryFilters(categories) {
    var container = document.getElementById('category-filters');
    container.innerHTML = '';
    var icons = {
        'Sedans': 'fas fa-car-side', 'Sports': 'fas fa-flag-checkered',
        'SUVs': 'fas fa-truck-monster', 'Supercars': 'fas fa-bolt',
        'Motorcycles': 'fas fa-motorcycle', 'Trucks': 'fas fa-truck',
    };
    categories.forEach(function(cat) {
        var btn = document.createElement('button');
        btn.className      = 'filter-btn';
        btn.dataset.filter = 'category';
        btn.dataset.value  = cat;
        btn.innerHTML      = '<i class="' + (icons[cat] || 'fas fa-car') + '"></i> ' + cat;
        btn.addEventListener('click', function() { setFilter('category', cat, btn); });
        container.appendChild(btn);
    });

    // Re-wire the static "All Categories" button — it's in HTML so its listener
    // fires at page load before categories exist. Re-attach here to be safe.
    var allBtn = document.querySelector('[data-filter="category"][data-value="all"]');
    if (allBtn) {
        allBtn.replaceWith(allBtn.cloneNode(true)); // remove old listener
        var freshAllBtn = document.querySelector('[data-filter="category"][data-value="all"]');
        freshAllBtn.addEventListener('click', function() {
            setFilter('category', 'all', freshAllBtn);
        });
    }
}

// ── Filter & Sort ─────────────────────────

function setFilter(type, value, btn) {
    if (type === 'tier') {
        activeTier = value;
        document.querySelectorAll('[data-filter="tier"]').forEach(function(b) { b.classList.remove('active'); });
    } else {
        activeCategory = value;
        document.querySelectorAll('[data-filter="category"]').forEach(function(b) { b.classList.remove('active'); });
    }
    btn.classList.add('active');
    renderVehicles();
}

document.querySelectorAll('[data-filter="tier"]').forEach(function(btn) {
    btn.addEventListener('click', function() { setFilter('tier', btn.dataset.value, btn); });
});

document.getElementById('sort-select').addEventListener('change', function(e) {
    activeSort = e.target.value;
    renderVehicles();
});

function getFilteredVehicles() {
    var vehicles = catalog.slice();
    if (activeTier !== 'all')     vehicles = vehicles.filter(function(v) { return v.tier === activeTier; });
    if (activeCategory !== 'all') vehicles = vehicles.filter(function(v) { return v.category === activeCategory; });
    if (activeSort === 'price-asc')  vehicles.sort(function(a,b) { return a.price - b.price; });
    if (activeSort === 'price-desc') vehicles.sort(function(a,b) { return b.price - a.price; });
    if (activeSort === 'name-asc')   vehicles.sort(function(a,b) { return a.label.localeCompare(b.label); });
    return vehicles;
}

// ── Render Vehicle Cards ──────────────────

function renderVehicles() {
    var grid     = document.getElementById('vehicle-grid');
    var vehicles = getFilteredVehicles();

    document.getElementById('result-count').textContent =
        vehicles.length + ' vehicle' + (vehicles.length !== 1 ? 's' : '');

    grid.innerHTML = '';
    if (vehicles.length === 0) {
        grid.innerHTML = '<div style="grid-column:1/-1;text-align:center;padding:60px 20px;color:#606080;">No vehicles match your filters.</div>';
        return;
    }
    vehicles.forEach(function(v) { grid.appendChild(buildVehicleCard(v)); });
}

// ── Vehicle preview image ────────────────────────────────────────────────────
// FiveM NUI cannot reach external CDNs (all external fetches are blocked).
// Images must be served from within the resource's html/ folder.
// Place a file named {model}.jpg inside html/img/ for each vehicle.
// e.g. html/img/sentinel.jpg, html/img/italirsx.jpg
// If no image is found, the tier icon fallback is shown instead.
// ─────────────────────────────────────────────────────────────────────────────

function getVehicleImageUrl(model) {
    return 'img/' + model.toLowerCase() + '.jpg';
}

function buildVehicleCard(vehicle) {
    var card = document.createElement('div');
    card.className = 'vehicle-card tier-' + vehicle.tier;

    var tierIcons = { standard: 'fas fa-car', elite: 'fas fa-star', apex: 'fas fa-crown' };
    var icon      = tierIcons[vehicle.tier] || 'fas fa-car';

    var priceDisplay = vehicle.price === 0
        ? '<span class="card-price free">FREE</span>'
        : '<span class="card-price">$' + vehicle.price.toLocaleString() + '</span>';

    var supplyDisplay = '', supplyClass = '';
    if (vehicle.limit === -1) {
        supplyDisplay = 'Unlimited';
    } else if (vehicle.remaining <= 0) {
        supplyDisplay = 'Sold Out'; supplyClass = 'sold'; card.classList.add('unavailable');
    } else if (vehicle.remaining <= 3) {
        supplyDisplay = vehicle.remaining + ' left'; supplyClass = 'low';
    } else {
        supplyDisplay = vehicle.remaining + ' / ' + vehicle.limit;
    }

    // Build preview image — onerror swaps to fallback icon
    var imgHtml =
        '<div class="card-preview">' +
            '<img src="' + getVehicleImageUrl(vehicle.model) + '" ' +
                'alt="' + vehicle.label + '" ' +
                'onerror="this.style.display=\'none\';this.nextSibling.style.display=\'flex\';" />' +
            '<div class="card-preview-fallback" style="display:none;">' +
                '<i class="' + icon + '"></i>' +
            '</div>' +
        '</div>';

    card.innerHTML =
        imgHtml +
        '<div class="card-top">' +
            '<div class="card-icon"><i class="' + icon + '"></i></div>' +
            '<span class="tier-badge">' + vehicle.tier + '</span>' +
        '</div>' +
        '<div class="card-label">' + vehicle.label + '</div>' +
        '<div class="card-description">' + vehicle.description + '</div>' +
        '<div class="card-bottom">' +
            priceDisplay +
            '<span class="card-supply ' + supplyClass + '">' + supplyDisplay + '</span>' +
        '</div>' +
        (vehicle.remaining <= 0 && vehicle.limit !== -1 ? '<div class="sold-overlay">SOLD OUT</div>' : '');

    if (!card.classList.contains('unavailable')) {
        card.addEventListener('click', function() { openConfirmModal(vehicle); });
    }
    return card;
}

// ── Purchase Modal ────────────────────────

function openConfirmModal(vehicle) {
    selectedVehicle = vehicle;
    document.getElementById('modal-vehicle-name').textContent = vehicle.label;
    document.getElementById('modal-tier').textContent         = vehicle.tier.toUpperCase();
    document.getElementById('modal-price').textContent        = vehicle.price === 0 ? 'FREE' : '$' + vehicle.price.toLocaleString();
    document.getElementById('modal-supply').textContent       = vehicle.limit === -1 ? 'Unlimited' : vehicle.remaining + ' remaining';
    document.getElementById('modal-balance').textContent      = '$' + balance.toLocaleString();

    var warning = '';
    if (vehicle.tier === 'elite' && tickets.elite < 1)
        warning = 'You do not have an Elite Ticket. Purchase one on Tebex.';
    else if (vehicle.tier === 'apex' && tickets.apex < 1)
        warning = 'You do not have an Apex Ticket. Purchase one on Tebex.';
    else if (vehicle.tier !== 'apex' && balance < vehicle.price)
        warning = 'Insufficient funds. Required: $' + vehicle.price.toLocaleString();

    document.getElementById('modal-ticket-warning').textContent = warning;
    document.getElementById('confirm-modal').classList.remove('hidden');
}

document.getElementById('modal-cancel').addEventListener('click', function() {
    document.getElementById('confirm-modal').classList.add('hidden');
    selectedVehicle = null;
});

document.getElementById('modal-testdrive').addEventListener('click', function() {
    if (!selectedVehicle) return;
    fetch('https://' + GetParentResourceName() + '/startSelfTestDrive', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: selectedVehicle.model })
    });
    document.getElementById('confirm-modal').classList.add('hidden');
    selectedVehicle = null;
});

document.getElementById('modal-confirm').addEventListener('click', function() {
    if (!selectedVehicle) return;
    // Hide modal immediately — server will close full UI after purchase completes
    // Do NOT call closeUI() here — that would close the UI before the server
    // has a chance to process the purchase and trigger spawnVehicle
    document.getElementById('confirm-modal').classList.add('hidden');
    fetch('https://' + GetParentResourceName() + '/purchaseVehicle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: selectedVehicle.model, tier: selectedVehicle.tier, price: selectedVehicle.price, label: selectedVehicle.label })
    });
    selectedVehicle = null;
});

// ── Boss Panel: Society Fund ──────────────

document.getElementById('btn-check-balance').addEventListener('click', function() {
    fetch('https://' + GetParentResourceName() + '/getSocietyBalance', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });
});

document.getElementById('btn-withdraw').addEventListener('click', function() {
    document.getElementById('society-balance-display'); // already visible
    document.getElementById('withdraw-modal').classList.remove('hidden');
    document.getElementById('withdraw-amount-input').value = '';
});

document.getElementById('withdraw-cancel').addEventListener('click', function() {
    document.getElementById('withdraw-modal').classList.add('hidden');
});

document.getElementById('withdraw-confirm').addEventListener('click', function() {
    var amount = parseInt(document.getElementById('withdraw-amount-input').value);
    if (!amount || amount <= 0) return;
    fetch('https://' + GetParentResourceName() + '/withdrawSociety', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ amount: amount })
    });
    document.getElementById('withdraw-modal').classList.add('hidden');
});

// ── Boss Panel: Staff Management ──────────

function openStaffModal(action, title) {
    staffModalAction = action;
    document.getElementById('staff-modal-title').textContent = title;
    document.getElementById('staff-modal-input').value = '';
    document.getElementById('staff-modal').classList.remove('hidden');
}

document.getElementById('btn-hire').addEventListener('click', function() {
    openStaffModal('hire', '👔 Hire Employee');
});
document.getElementById('btn-fire').addEventListener('click', function() {
    openStaffModal('fire', '🚪 Fire Employee');
});
document.getElementById('btn-promote').addEventListener('click', function() {
    openStaffModal('promote', '⬆️ Promote Employee');
});
document.getElementById('btn-demote').addEventListener('click', function() {
    openStaffModal('demote', '⬇️ Demote Employee');
});

document.getElementById('staff-modal-cancel').addEventListener('click', function() {
    document.getElementById('staff-modal').classList.add('hidden');
    staffModalAction = null;
});

document.getElementById('staff-modal-confirm').addEventListener('click', function() {
    var targetId = parseInt(document.getElementById('staff-modal-input').value);
    if (!targetId || targetId <= 0 || !staffModalAction) return;

    var endpoint = staffModalAction + 'Player';
    fetch('https://' + GetParentResourceName() + '/' + endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ targetId: targetId })
    });

    document.getElementById('staff-modal').classList.add('hidden');
    staffModalAction = null;
});


// ── Sales Stats + Leaderboard ─────────────────────────────────────────────────

var currentStatsPeriod = 'today';

function loadSalesStats(period) {
    currentStatsPeriod = period || 'today';

    // Update toggle buttons
    ['today', 'week', 'alltime'].forEach(function(p) {
        var btn = document.getElementById('stats-period-' + p);
        if (btn) btn.classList.toggle('active', p === currentStatsPeriod);
    });

    // Show loading
    document.getElementById('stat-units').textContent   = '—';
    document.getElementById('stat-revenue').textContent = '—';
    document.getElementById('stat-commission').textContent = '—';

    fetch('https://' + GetParentResourceName() + '/getSalesStats', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ period: currentStatsPeriod })
    });
}

function loadLeaderboard() {
    document.getElementById('leaderboard-content').innerHTML =
        '<div class="stats-loading"><i class="fas fa-spinner fa-spin"></i> Loading...</div>';
    fetch('https://' + GetParentResourceName() + '/getSalesLeaderboard', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });
}

// Receive stats from server
window.addEventListener('message', function(event) {
    if (event.data.action === 'receiveSalesStats') {
        var d = event.data;
        var label = { today: 'today', week: 'this week', alltime: 'all time' }[currentStatsPeriod] || '';
        document.getElementById('stat-units').textContent        = d.units || 0;
        document.getElementById('stat-units-sub').textContent    = 'vehicles sold ' + label;
        document.getElementById('stat-revenue').textContent      = '$' + (d.revenue || 0).toLocaleString();
        document.getElementById('stat-revenue-sub').textContent  = 'gross revenue ' + label;
        document.getElementById('stat-commission').textContent   = '$' + (d.commission || 0).toLocaleString();
        document.getElementById('stat-commission-sub').textContent = 'paid out ' + label;
    }

    if (event.data.action === 'receiveLeaderboard') {
        var entries = event.data.entries || [];
        if (entries.length === 0) {
            document.getElementById('leaderboard-content').innerHTML =
                '<div class="stats-loading">No sales recorded yet.</div>';
            return;
        }
        var rankClasses = ['gold', 'silver', 'bronze'];
        var rows = entries.map(function(e, i) {
            var rankClass = rankClasses[i] ? ' class="lb-rank ' + rankClasses[i] + '"' : ' class="lb-rank"';
            var medal     = i === 0 ? '🥇' : i === 1 ? '🥈' : i === 2 ? '🥉' : (i + 1) + '.';
            return '<tr>' +
                '<td' + rankClass + '>' + medal + '</td>' +
                '<td><div class="lb-name">' + (e.name || e.citizenid) + '</div>' +
                    '<div class="lb-grade">' + (e.grade || '') + '</div></td>' +
                '<td class="lb-sales">' + e.sales + ' sales</td>' +
                '<td class="lb-revenue">$' + (e.revenue || 0).toLocaleString() + '</td>' +
            '</tr>';
        }).join('');
        document.getElementById('leaderboard-content').innerHTML =
            '<table class="leaderboard-table">' +
                '<thead><tr>' +
                    '<th>#</th><th>Employee</th><th>Sales</th><th>Revenue</th>' +
                '</tr></thead>' +
                '<tbody>' + rows + '</tbody>' +
            '</table>';
    }
});

document.getElementById('btn-refresh-stats').addEventListener('click', function() {
    loadSalesStats(currentStatsPeriod);
    loadLeaderboard();
});

// Auto-load when boss tab opens
document.querySelectorAll('.tab-btn').forEach(function(btn) {
    btn.addEventListener('click', function() {
        if (btn.dataset.tab === 'boss') {
            setTimeout(function() {
                loadSalesStats('today');
                loadLeaderboard();
            }, 100);
        }
    });
});

// ─────────────────────────────────────────────────────────────────────────────

// ── Close UI ──────────────────────────────

document.getElementById('close-btn').addEventListener('click', closeUI);

// ESC or Backspace closes UI — NUI intercepts keys so we handle it here
// and fire the same closeUI NUI callback that the Lua ESC thread listens for
document.addEventListener('keydown', function(e) {
    if (e.key === 'Escape' || e.key === 'Backspace') {
        // Don't close if user is typing in an input field
        if (document.activeElement && (
            document.activeElement.tagName === 'INPUT' ||
            document.activeElement.tagName === 'TEXTAREA'
        )) return;
        closeUI();
    }
});

function closeUI() {
    document.getElementById('dealership-ui').classList.add('hidden');
    document.getElementById('confirm-modal').classList.add('hidden');
    document.getElementById('staff-modal').classList.add('hidden');
    document.getElementById('withdraw-modal').classList.add('hidden');

    fetch('https://' + GetParentResourceName() + '/closeUI', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({})
    });

    // Reset state
    activeTier      = 'all';
    activeCategory  = 'all';
    activeSort      = 'default';
    selectedVehicle = null;

    // Reset filter button active states so next open starts clean
    document.querySelectorAll('[data-filter="tier"]').forEach(function(b) {
        b.classList.toggle('active', b.dataset.value === 'all');
    });
    document.querySelectorAll('[data-filter="category"]').forEach(function(b) {
        b.classList.toggle('active', b.dataset.value === 'all');
    });
    var sortSelect = document.getElementById('sort-select');
    if (sortSelect) sortSelect.value = 'default';
}

console.log('[FD] script.js v2.0 fully loaded.');
