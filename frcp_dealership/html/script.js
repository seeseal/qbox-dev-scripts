// ============================================
//  fd_dealership | script.js
// ============================================

console.log('[FD] script.js starting...');

let catalog        = [];
let tickets        = { elite: 0, apex: 0 };
let balance        = 0;
let activeTier     = 'all';
let activeCategory = 'all';
let activeSort     = 'default';
let selectedVehicle = null;

// ============================================
//  NUI Message Handler
// ============================================

window.addEventListener('message', function(event) {
    console.log('[FD] message received:', event.data.action);

    var action        = event.data.action;
    var data          = event.data.data;
    var tiers         = event.data.tiers;
    var categories    = event.data.categories;
    var dealershipName = event.data.dealershipName;

    if (action === 'openDealership') {
        console.log('[FD] openDealership called');
        console.log('[FD] data:', JSON.stringify(data).substring(0, 100));

        try {
            catalog  = data.catalog;
            tickets  = data.tickets;
            balance  = data.balance;

            console.log('[FD] catalog length:', catalog.length);
            console.log('[FD] setting text fields...');

            document.getElementById('dealership-name').textContent = dealershipName;
            document.getElementById('player-name').textContent     = 'Welcome, ' + data.playerName;
            document.getElementById('player-balance').textContent  = '$' + balance.toLocaleString();
            document.getElementById('ticket-elite').textContent    = tickets.elite;
            document.getElementById('ticket-apex').textContent     = tickets.apex;

            console.log('[FD] building category filters...');
            buildCategoryFilters(categories);

            console.log('[FD] rendering vehicles...');
            renderVehicles();

            console.log('[FD] removing hidden class...');
            document.getElementById('dealership-ui').classList.remove('hidden');
            console.log('[FD] UI should be visible now');

        } catch(err) {
            console.error('[FD] ERROR in openDealership:', err.message, err.stack);
        }
    }

    if (action === 'closeUI') {
        console.log('[FD] closeUI called');
        closeUI();
    }
});

console.log('[FD] message listener registered');

// ============================================
//  Build Category Filter Buttons
// ============================================

function buildCategoryFilters(categories) {
    var container = document.getElementById('category-filters');
    container.innerHTML = '';

    var icons = {
        'Sedans':      'fas fa-car-side',
        'Sports':      'fas fa-flag-checkered',
        'SUVs':        'fas fa-truck-monster',
        'Supercars':   'fas fa-bolt',
        'Motorcycles': 'fas fa-motorcycle',
        'Trucks':      'fas fa-truck',
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
}

// ============================================
//  Filter & Sort Logic
// ============================================

function setFilter(type, value, btn) {
    if (type === 'tier') {
        activeTier = value;
        document.querySelectorAll('[data-filter="tier"]').forEach(function(b) {
            b.classList.remove('active');
        });
    } else {
        activeCategory = value;
        document.querySelectorAll('[data-filter="category"]').forEach(function(b) {
            b.classList.remove('active');
        });
    }
    btn.classList.add('active');
    renderVehicles();
}

// Bind tier filter buttons
document.querySelectorAll('[data-filter="tier"]').forEach(function(btn) {
    btn.addEventListener('click', function() {
        setFilter('tier', btn.dataset.value, btn);
    });
});

// Bind sort dropdown
document.getElementById('sort-select').addEventListener('change', function(e) {
    activeSort = e.target.value;
    renderVehicles();
});

function getFilteredVehicles() {
    var vehicles = catalog.slice();

    if (activeTier !== 'all') {
        vehicles = vehicles.filter(function(v) { return v.tier === activeTier; });
    }
    if (activeCategory !== 'all') {
        vehicles = vehicles.filter(function(v) { return v.category === activeCategory; });
    }

    if (activeSort === 'price-asc')  vehicles.sort(function(a,b) { return a.price - b.price; });
    if (activeSort === 'price-desc') vehicles.sort(function(a,b) { return b.price - a.price; });
    if (activeSort === 'name-asc')   vehicles.sort(function(a,b) { return a.label.localeCompare(b.label); });

    return vehicles;
}

// ============================================
//  Render Vehicle Cards
// ============================================

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

    vehicles.forEach(function(vehicle) {
        var card = buildVehicleCard(vehicle);
        grid.appendChild(card);
    });
}

function buildVehicleCard(vehicle) {
    var card = document.createElement('div');
    card.className = 'vehicle-card tier-' + vehicle.tier;

    var tierIcons = { standard: 'fas fa-car', elite: 'fas fa-star', apex: 'fas fa-crown' };
    var icon      = tierIcons[vehicle.tier] || 'fas fa-car';

    var priceDisplay = vehicle.price === 0
        ? '<span class="card-price free">FREE</span>'
        : '<span class="card-price">$' + vehicle.price.toLocaleString() + '</span>';

    var supplyDisplay = '';
    var supplyClass   = '';

    if (vehicle.limit === -1) {
        supplyDisplay = 'Unlimited';
    } else if (vehicle.remaining <= 0) {
        supplyDisplay = 'Sold Out';
        supplyClass   = 'sold';
        card.classList.add('unavailable');
    } else if (vehicle.remaining <= 3) {
        supplyDisplay = vehicle.remaining + ' left';
        supplyClass   = 'low';
    } else {
        supplyDisplay = vehicle.remaining + ' / ' + vehicle.limit;
    }

    card.innerHTML =
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

// ============================================
//  Confirm Modal
// ============================================

function openConfirmModal(vehicle) {
    selectedVehicle = vehicle;

    document.getElementById('modal-vehicle-name').textContent = vehicle.label;
    document.getElementById('modal-tier').textContent         = vehicle.tier.toUpperCase();
    document.getElementById('modal-price').textContent        = vehicle.price === 0 ? 'FREE' : '$' + vehicle.price.toLocaleString();
    document.getElementById('modal-supply').textContent       = vehicle.limit === -1 ? 'Unlimited' : vehicle.remaining + ' remaining';
    document.getElementById('modal-balance').textContent      = '$' + balance.toLocaleString();

    var warning = '';
    if (vehicle.tier === 'elite' && tickets.elite < 1) {
        warning = 'You do not have an Elite Ticket. Purchase one on Tebex.';
    } else if (vehicle.tier === 'apex' && tickets.apex < 1) {
        warning = 'You do not have an Apex Ticket. Purchase one on Tebex.';
    } else if (vehicle.tier !== 'apex' && balance < vehicle.price) {
        warning = 'Insufficient funds. Required: $' + vehicle.price.toLocaleString();
    }

    document.getElementById('modal-ticket-warning').textContent = warning;
    document.getElementById('confirm-modal').classList.remove('hidden');
}

document.getElementById('modal-cancel').addEventListener('click', function() {
    document.getElementById('confirm-modal').classList.add('hidden');
    selectedVehicle = null;
});

document.getElementById('modal-confirm').addEventListener('click', function() {
    if (!selectedVehicle) return;

    fetch('https://' + GetParentResourceName() + '/purchaseVehicle', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ model: selectedVehicle.model })
    });

    document.getElementById('confirm-modal').classList.add('hidden');
    selectedVehicle = null;
});

// ============================================
//  Close UI
// ============================================

document.getElementById('close-btn').addEventListener('click', closeUI);

function closeUI() {
    console.log('[FD] closeUI called');
    document.getElementById('dealership-ui').classList.add('hidden');
    document.getElementById('confirm-modal').classList.add('hidden');

    fetch('https://' + GetParentResourceName() + '/closeUI', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });

    activeTier      = 'all';
    activeCategory  = 'all';
    selectedVehicle = null;
}

console.log('[FD] script.js fully loaded');