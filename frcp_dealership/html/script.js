// ============================================
//  fd_dealership | script.js
//  Handles all UI logic and NUI communication
// ============================================

let catalog       = [];
let tickets       = { elite: 0, apex: 0 };
let balance       = 0;
let activeTier    = 'all';
let activeCategory = 'all';
let activeSort    = 'default';
let selectedVehicle = null;

// ============================================
//  NUI Message Handler
//  Receives data from Lua client
// ============================================

window.addEventListener('message', (event) => {
    const { action, data, tiers, categories, dealershipName } = event.data;

    if (action === 'openDealership') {
        catalog   = data.catalog;
        tickets   = data.tickets;
        balance   = data.balance;

        document.getElementById('dealership-name').textContent = dealershipName;
        document.getElementById('player-name').textContent     = 'Welcome, ' + data.playerName;
        document.getElementById('player-balance').textContent  = '$' + balance.toLocaleString();
        document.getElementById('ticket-elite').textContent    = tickets.elite;
        document.getElementById('ticket-apex').textContent     = tickets.apex;

        buildCategoryFilters(categories);
        renderVehicles();

        document.getElementById('dealership-ui').classList.remove('hidden');
    }

    if (action === 'closeUI') {
        closeUI();
    }
});

// ============================================
//  Build Category Filter Buttons
// ============================================

function buildCategoryFilters(categories) {
    const container = document.getElementById('category-filters');
    container.innerHTML = '';

    const icons = {
        'Sedans':      'fas fa-car-side',
        'Sports':      'fas fa-flag-checkered',
        'SUVs':        'fas fa-truck-monster',
        'Supercars':   'fas fa-bolt',
        'Motorcycles': 'fas fa-motorcycle',
        'Trucks':      'fas fa-truck',
    };

    categories.forEach(cat => {
        const btn = document.createElement('button');
        btn.className    = 'filter-btn';
        btn.dataset.filter = 'category';
        btn.dataset.value  = cat;
        btn.innerHTML    = `<i class="${icons[cat] || 'fas fa-car'}"></i> ${cat}`;
        btn.addEventListener('click', () => setFilter('category', cat, btn));
        container.appendChild(btn);
    });
}

// ============================================
//  Filter & Sort Logic
// ============================================

function setFilter(type, value, btn) {
    if (type === 'tier') {
        activeTier = value;
        document.querySelectorAll('[data-filter="tier"]').forEach(b => b.classList.remove('active'));
    } else {
        activeCategory = value;
        document.querySelectorAll('[data-filter="category"]').forEach(b => b.classList.remove('active'));
    }
    btn.classList.add('active');
    renderVehicles();
}

document.querySelectorAll('[data-filter="tier"]').forEach(btn => {
    btn.addEventListener('click', () => setFilter('tier', btn.dataset.value, btn));
});

document.getElementById('sort-select').addEventListener('change', (e) => {
    activeSort = e.target.value;
    renderVehicles();
});

function getFilteredVehicles() {
    let vehicles = [...catalog];

    if (activeTier !== 'all') {
        vehicles = vehicles.filter(v => v.tier === activeTier);
    }

    if (activeCategory !== 'all') {
        vehicles = vehicles.filter(v => v.category === activeCategory);
    }

    switch (activeSort) {
        case 'price-asc':  vehicles.sort((a,b) => a.price - b.price); break;
        case 'price-desc': vehicles.sort((a,b) => b.price - a.price); break;
        case 'name-asc':   vehicles.sort((a,b) => a.label.localeCompare(b.label)); break;
    }

    return vehicles;
}

// ============================================
//  Render Vehicle Cards
// ============================================

function renderVehicles() {
    const grid     = document.getElementById('vehicle-grid');
    const vehicles = getFilteredVehicles();

    document.getElementById('result-count').textContent = vehicles.length + ' vehicle' + (vehicles.length !== 1 ? 's' : '');

    grid.innerHTML = '';

    if (vehicles.length === 0) {
        grid.innerHTML = `
            <div style="grid-column:1/-1; text-align:center; padding:60px 20px; color:#606080;">
                <i class="fas fa-search" style="font-size:32px; margin-bottom:12px; display:block;"></i>
                No vehicles match your filters.
            </div>`;
        return;
    }

    vehicles.forEach(vehicle => {
        const card = buildVehicleCard(vehicle);
        grid.appendChild(card);
    });
}

function buildVehicleCard(vehicle) {
    const card = document.createElement('div');
    card.className = `vehicle-card tier-${vehicle.tier}`;

    const tierIcons = { standard: 'fas fa-car', elite: 'fas fa-star', apex: 'fas fa-crown' };
    const icon      = tierIcons[vehicle.tier] || 'fas fa-car';

    const priceDisplay = vehicle.price === 0
        ? `<span class="card-price free">FREE</span>`
        : `<span class="card-price">$${vehicle.price.toLocaleString()}</span>`;

    let supplyDisplay = '';
    let supplyClass   = '';

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

    card.innerHTML = `
        <div class="card-top">
            <div class="card-icon"><i class="${icon}"></i></div>
            <span class="tier-badge">${vehicle.tier}</span>
        </div>
        <div class="card-label">${vehicle.label}</div>
        <div class="card-description">${vehicle.description}</div>
        <div class="card-bottom">
            ${priceDisplay}
            <span class="card-supply ${supplyClass}">${supplyDisplay}</span>
        </div>
        ${vehicle.remaining <= 0 && vehicle.limit !== -1 ? '<div class="sold-overlay">SOLD OUT</div>' : ''}
    `;

    if (!card.classList.contains('unavailable')) {
        card.addEventListener('click', () => openConfirmModal(vehicle));
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

    // Ticket warning
    let warning = '';
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

document.getElementById('modal-cancel').addEventListener('click', () => {
    document.getElementById('confirm-modal').classList.add('hidden');
    selectedVehicle = null;
});

document.getElementById('modal-confirm').addEventListener('click', () => {
    if (!selectedVehicle) return;

    fetch(`https://${GetParentResourceName()}/purchaseVehicle`, {
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
    document.getElementById('dealership-ui').classList.add('hidden');
    document.getElementById('confirm-modal').classList.add('hidden');

    fetch(`https://${GetParentResourceName()}/closeUI`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({})
    });

    // Reset filters
    activeTier     = 'all';
    activeCategory = 'all';
    selectedVehicle = null;
}
```

---

Save all three files and push to GitHub.

Commit message:
```

```

---

That's the full dealership script — all 6 files complete. Tonight at home the test checklist is:

1. Pull from GitHub
2. Run both SQL files in phpMyAdmin
3. Copy `discord_webhook`, `tebex_tickets`, `fd_dealership` into `[custom]`
4. Add to `server.cfg`:
```
ensure discord_webhook
ensure tebex_tickets
ensure fd_dealership