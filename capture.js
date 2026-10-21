/*
 * BandLock — penangkap sesi diag modemcaps (Frida, native hooks saja)
 *
 * Mengait di proses ru.fieldtest.modemcaps:
 *  - libc open/openat  : lacak fd untuk "/dev/diag"
 *  - libc connect      : lacak socket abstrak "diag" (bila cabang socket aktif)
 *  - libc ioctl        : untuk fd terlacak — request, arg (hex 32B bila
 *                        pointer masuk akal), hasil + errno
 *  - libc write/read   : untuk fd terlacak — byte kawat (maks 256B) + hasil
 *  - liba.so by offset : g() (0x278C, argumen + nilai kembali jlong),
 *                        o() (0x3EB4, len bertanda + to1 + to2),
 *                        n() (0x461C, handle kembali), k() (0x26A0, argumen)
 * Semua baris berawalan [BLCAP] agar mudah disaring. Read-only: skrip ini
 * TIDAK mengubah argumen/byte apa pun — murni mencatat.
 */
'use strict';

var T0 = Date.now();
function ts() { return '+' + (Date.now() - T0) + 'ms'; }
function log(s) { console.log('[BLCAP] ' + ts() + ' ' + s); }

function hex(p, n) {
  try {
    var bytes = new Uint8Array(Memory.readByteArray(p, n));
    var out = '';
    for (var i = 0; i < bytes.length; i++) {
      out += ('0' + bytes[i].toString(16)).slice(-2) + ' ';
      if (i % 16 === 15) out += ' ';
    }
    return out.trim();
  } catch (e) { return '<tak terbaca>'; }
}
function looksPtr(v) {
  try { var n = v.toNumber ? v.toNumber() : parseInt(v); return n > 0x10000 && n < 0x800000000000; }
  catch (e) { return false; }
}

var diagFds = {};   // fd -> label

function libc(name) {
  var m = Process.findModuleByName('libc.so');
  return m ? m.findExportByName(name) : Module.findGlobalExportByName(name);
}

/* ---------- open/openat: lacak /dev/diag ---------- */
['open', 'openat'].forEach(function (fname) {
  var addr = libc(fname);
  if (!addr) return;
  Interceptor.attach(addr, {
    onEnter: function (args) {
      var pathArg = (fname === 'openat') ? args[1] : args[0];
      try { this.path = pathArg.readCString(); } catch (e) { this.path = null; }
    },
    onLeave: function (retval) {
      if (this.path && this.path.indexOf('/dev/diag') !== -1) {
        var fd = retval.toInt32();
        if (fd >= 0) { diagFds[fd] = 'diag-char'; log('OPEN ' + this.path + ' -> fd=' + fd); }
      }
    }
  });
});

/* ---------- connect: lacak socket abstrak diag ---------- */
(function () {
  var addr = libc('connect');
  if (!addr) return;
  Interceptor.attach(addr, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      this.isDiagSock = false;
      try {
        var fam = args[1].readU16();
        if (fam === 1) { // AF_UNIX
          var first = args[1].add(2).readU8();
          var name = '';
          if (first === 0) { // abstrak: byte pertama nama sesudah NUL
            name = args[1].add(3).readCString(16) || '';
          } else {
            name = args[1].add(2).readCString(64) || '';
          }
          if (name.indexOf('diag') !== -1) { this.isDiagSock = true; this.name = name; }
        }
      } catch (e) {}
    },
    onLeave: function (retval) {
      if (this.isDiagSock) {
        diagFds[this.fd] = 'diag-sock';
        log('CONNECT @' + this.name + ' fd=' + this.fd + ' -> ' + retval.toInt32());
      }
    }
  });
})();

/* ---------- ioctl pada fd terlacak ---------- */
(function () {
  var addr = libc('ioctl');
  if (!addr) return;
  Interceptor.attach(addr, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      if (!(this.fd in diagFds)) { this.skip = true; return; }
      this.req = args[1];
      this.arg = args[2];
      var line = 'IOCTL fd=' + this.fd + ' req=' + this.req.toString() +
                 ' (0x' + this.req.toString(16) + ') arg=' + this.arg;
      if (looksPtr(this.arg)) line += ' argBytes=[ ' + hex(this.arg, 32) + ' ]';
      log(line);
    },
    onLeave: function (retval) {
      if (this.skip) return;
      var line = 'IOCTL fd=' + this.fd + ' req=' + this.req.toString() +
                 ' -> ' + retval.toInt32() + ' errno=' + this.errno;
      if (looksPtr(this.arg)) line += ' argBytesSesudah=[ ' + hex(this.arg, 32) + ' ]';
      log(line);
    }
  });
})();

/* ---------- write/read pada fd terlacak ---------- */
(function () {
  var waddr = libc('write');
  if (waddr) Interceptor.attach(waddr, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      if (!(this.fd in diagFds)) { this.skip = true; return; }
      this.len = args[2].toInt32();
      log('WRITE fd=' + this.fd + ' len=' + this.len + ' [ ' + hex(args[1], Math.min(this.len, 256)) + ' ]');
    },
    onLeave: function (retval) {
      if (this.skip) return;
      log('WRITE fd=' + this.fd + ' -> ' + retval.toInt32() + ' errno=' + this.errno);
    }
  });
  var raddr = libc('read');
  if (raddr) Interceptor.attach(raddr, {
    onEnter: function (args) {
      this.fd = args[0].toInt32();
      if (!(this.fd in diagFds)) { this.skip = true; return; }
      this.buf = args[1];
    },
    onLeave: function (retval) {
      if (this.skip) return;
      var n = retval.toInt32();
      var line = 'READ fd=' + this.fd + ' -> ' + n + ' errno=' + this.errno;
      if (n > 0) line += ' [ ' + hex(this.buf, Math.min(n, 256)) + ' ]';
      log(line);
    }
  });
})();

/* ---------- liba.so: fungsi JNI by offset ---------- */
var OFF = { g: 0x278C, o: 0x3EB4, n: 0x461C, k: 0x26A0 };
var libaHooked = false;
function hookLiba(base) {
  if (libaHooked) return;
  libaHooked = true;
  log('liba.so base=' + base);
  try {
    Interceptor.attach(base.add(OFF.g), {
      onEnter: function (args) {
        log('G() masuk: a1=' + args[2] + ' a2=' + args[3] + ' a3=' + args[4] +
            ' a4=' + args[5] + ' a5=' + args[6]);
        this.tid = this.threadId;
      },
      onLeave: function (retval) {
        var v = retval;
        var hexv = '';
        try { hexv = '0x' + v.toString(16); } catch (e) {}
        log('G() kembali: ' + v + ' (' + hexv + ')  [bit B(12-14) & A(15-17) & C(21-23) terbaca dari nilai ini]');
      }
    });
  } catch (e) { log('hook g gagal: ' + e); }
  try {
    Interceptor.attach(base.add(OFF.o), {
      onEnter: function (args) {
        var len = args[5].toInt32();
        log('O() handle=' + args[2] + ' len=' + len + ' to1=' + args[6] + ' (0x' + args[6].toString(16) + ')' +
            ' to2=' + args[7] + (len < 0 ? ' [TERIMA]' : ' [KIRIM]'));
      },
      onLeave: function (retval) { log('O() -> ' + retval.toInt32()); }
    });
  } catch (e) { log('hook o gagal: ' + e); }
  try {
    Interceptor.attach(base.add(OFF.n), {
      onLeave: function (retval) { log('N() -> handle ' + retval + ' (0x' + retval.toString(16) + ')'); }
    });
  } catch (e) { log('hook n gagal: ' + e); }
  try {
    Interceptor.attach(base.add(OFF.k), {
      onEnter: function (args) {
        log('K() masuk: x2=' + args[2] + ' x3=' + args[3] + ' x4=' + args[4] +
            ' x5=' + args[5] + ' x6=' + args[6] + ' x7=' + args[7]);
      },
      onLeave: function (retval) { log('K() -> ' + retval); }
    });
  } catch (e) { log('hook k gagal: ' + e); }
}

var timer = setInterval(function () {
  var m = Process.findModuleByName('liba.so');
  if (m) { hookLiba(m.base); clearInterval(timer); }
}, 400);

log('penangkap BandLock aktif — semua hook libc terpasang, menunggu liba.so.');
