// parse_itemcache.js
// Le o itemcache.wdb do WoW 1.12 e gera items_db.json para o site
// Uso: node parse_itemcache.js

const fs   = require('fs');
const path = require('path');

const WDB_PATH  = 'D:\\jogos\\WoW-SandWorlds\\WDB\\itemcache.wdb';
const OUT_PATH  = path.join(__dirname, 'items_db.json');

// Inventory type -> nome do slot
const INV_TYPE = {
  0:'',1:'Cabeça',2:'Pescoço',3:'Ombros',4:'Corpo',5:'Peito',
  6:'Cintura',7:'Pernas',8:'Pés',9:'Pulso',10:'Mãos',11:'Dedo',
  12:'Trinket',13:'Arma 1M',14:'Escudo',15:'Arco',16:'Costas',
  17:'Arma 2M',18:'Mochila',19:'Tabardo',20:'Peito',21:'Mão Principal',
  22:'Mão Secundária',23:'Segurar',24:'Projétil',25:'Jogue',26:'Munição',
  27:'Roupa',28:'Off-Hand',
};

// Item class -> subclass map (simplificado vanilla 1.12)
const ITEM_CLASS = {
  0: 'Consumível', 1: 'Container', 2: 'Arma', 3: 'Gema',
  4: 'Armadura',   5: 'Reagente',  6: 'Projétil', 7: 'Material de Ofício',
  9: 'Receita',   10: 'Moeda',    11: 'Missão',  12: 'Chave',
  15: 'Diversos',
};

const ARMOR_SUBCLASS = {
  0:'Diversos', 1:'Pano', 2:'Couro', 3:'Malha', 4:'Placa',
  6:'Escudo', 7:'Libretto', 10:'Costas',
};

const WEAPON_SUBCLASS = {
  0:'Machado 1M',1:'Machado 2M',2:'Arco',3:'Arma de Fogo',4:'Maça 1M',
  5:'Maça 2M',6:'Lança',7:'Espada 1M',8:'Espada 2M',9:'Obsoleto',
  10:'Bastão',11:'Arma de Arremesso',13:'Punho',14:'Diversos',
  15:'Adaga',16:'Montaria',19:'Varinha',20:'Cajado',
};

// Stat types
const STAT_TYPE = {
  1:'Saúde',2:'Mana',3:'Agilidade',4:'Força',5:'Intelecto',
  6:'Espírito',7:'Estamina',12:'Def.',13:'Esquiva',14:'Aparo',
  15:'Bloqueio',16:'Magia Sagrada',17:'Magia Fogo',18:'Magia Natureza',
  19:'Magia Gelo',20:'Magia Sombra',21:'Magia Arcana',22:'Cura',
  45:'Cura',
};

function readString(buf, offset) {
  let end = offset;
  while (end < buf.length && buf[end] !== 0) end++;
  return { str: buf.toString('utf8', offset, end), next: end + 1 };
}

function parseItems(buf) {
  const items = {};

  // Header: 4 magic + 4 build + 4 locale + 4 unk1 + 4 unk2 = 20 bytes
  let pos = 20;

  let count = 0;
  let skipped = 0;

  while (pos + 8 <= buf.length) {
    const id   = buf.readUInt32LE(pos);
    const size = buf.readUInt32LE(pos + 4);
    pos += 8;

    if (id === 0) break;

    if (size === 0) {
      // Registro vazio (placeholder)
      skipped++;
      continue;
    }

    if (pos + size > buf.length) break;

    const rec = buf.slice(pos, pos + size);
    pos += size;

    try {
      let r = 0;

      const itemClass    = rec.readUInt32LE(r); r += 4;
      const itemSubClass = rec.readUInt32LE(r); r += 4;

      // Nomes (4 strings null-terminated)
      const n1 = readString(rec, r); r = n1.next;
      const n2 = readString(rec, r); r = n2.next;
      const n3 = readString(rec, r); r = n3.next;
      const n4 = readString(rec, r); r = n4.next;

      const name = n1.str || n2.str || n3.str || n4.str;
      if (!name) { skipped++; continue; }

      const displayId    = rec.readUInt32LE(r); r += 4;
      const quality      = rec.readUInt32LE(r); r += 4;
      r += 4; // flags
      r += 4; // buyPrice
      r += 4; // sellPrice
      const inventoryType = rec.readUInt32LE(r); r += 4;
      r += 4; // allowableClass
      r += 4; // allowableRace
      const itemLevel    = rec.readUInt32LE(r); r += 4;
      const reqLevel     = rec.readUInt32LE(r); r += 4;
      r += 4; // reqSkill
      r += 4; // reqSkillRank
      r += 4; // reqSpell
      r += 4; // reqHonorRank
      r += 4; // reqCityRank
      r += 4; // reqRepFaction
      r += 4; // reqRepRank
      r += 4; // maxCount
      r += 4; // stackable
      r += 4; // containerSlots

      // 10 stat types + 10 stat values
      const statTypes  = [];
      const statValues = [];
      for (let i = 0; i < 10; i++) statTypes.push(rec.readUInt32LE(r + i*4));
      r += 40;
      for (let i = 0; i < 10; i++) statValues.push(rec.readInt32LE(r + i*4));
      r += 40;

      // Damage (5 × dmgMin, dmgMax, dmgType = 5×3 = 15 floats/ints but mixed)
      let dmgMin = 0, dmgMax = 0;
      for (let i = 0; i < 5; i++) {
        const mn = rec.readFloatLE(r); r += 4;
        const mx = rec.readFloatLE(r); r += 4;
        r += 4; // dmgType
        if (i === 0) { dmgMin = mn; dmgMax = mx; }
      }

      const armor    = rec.readUInt32LE(r); r += 4;
      r += 6 * 4; // resistances (holy fire nature frost shadow arcane)
      const delay    = rec.readUInt32LE(r); r += 4; // weapon speed ms
      r += 4; // ammoType
      r += 4; // rangedModRange (float)

      // 5 spells: spellId, trigger, charges, cooldown, category, catCooldown = 6 fields each
      r += 5 * 6 * 4;

      const bonding  = rec.readUInt32LE(r); r += 4;

      // Description string
      let desc = '';
      if (r < rec.length) {
        const ds = readString(rec, r); r = ds.next;
        desc = ds.str;
      }

      // Build stats array
      const stats = [];
      for (let i = 0; i < 10; i++) {
        if (statTypes[i] > 0 && statValues[i] !== 0) {
          const label = STAT_TYPE[statTypes[i]] || ('Stat'+statTypes[i]);
          stats.push({ type: statTypes[i], label, value: statValues[i] });
        }
      }

      // Tipo e subtipo
      let typeName = ITEM_CLASS[itemClass] || '';
      let subtypeName = '';
      if (itemClass === 4) subtypeName = ARMOR_SUBCLASS[itemSubClass] || '';
      else if (itemClass === 2) subtypeName = WEAPON_SUBCLASS[itemSubClass] || '';

      const slotName = INV_TYPE[inventoryType] || '';

      // Bonding
      const BONDING = {0:'',1:'Vincula ao pegar',2:'Vincula ao equipar',3:'Vincula ao usar',4:'Não comercializável'};
      const bindStr = BONDING[bonding] || '';

      items[id] = {
        id,
        name,
        quality,
        ilvl:     itemLevel,
        reqLevel,
        itype:    typeName,
        isubtype: subtypeName,
        slot:     slotName,
        armor:    armor || 0,
        dmgMin:   Math.round(dmgMin),
        dmgMax:   Math.round(dmgMax),
        speed:    delay,
        stats,
        bind:     bindStr,
        desc:     desc || '',
      };

      count++;
    } catch(e) {
      skipped++;
    }
  }

  return { items, count, skipped };
}

console.log('Lendo', WDB_PATH, '...');
const buf = fs.readFileSync(WDB_PATH);
console.log('Tamanho:', (buf.length/1024).toFixed(1), 'KB');

// Mostra magic/header
const magic = buf.toString('ascii', 0, 4);
const build = buf.readUInt32LE(4);
const locale = buf.toString('ascii', 8, 12);
console.log('Magic:', magic, '| Build:', build, '| Locale:', locale);

const { items, count, skipped } = parseItems(buf);
console.log('Itens parseados:', count, '| Ignorados:', skipped);

// Salva JSON compacto
const json = JSON.stringify(items);
fs.writeFileSync(OUT_PATH, json);
console.log('Salvo em:', OUT_PATH, '('+(json.length/1024).toFixed(1)+'KB)');

// Preview de alguns itens
const sample = Object.values(items).filter(i => i.quality >= 3).slice(0, 5);
console.log('\nSample (raro+):');
sample.forEach(i => console.log(` [${i.id}] ${i.name} | Q${i.quality} | ilvl${i.ilvl} | ${i.isubtype} | ${i.stats.map(s=>s.label+'+'+s.value).join(', ')}`));
