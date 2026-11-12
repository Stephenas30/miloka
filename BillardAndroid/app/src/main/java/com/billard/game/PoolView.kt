package com.billard.game

import android.content.Context
import android.graphics.BitmapFactory
import android.graphics.*
import android.util.AttributeSet
import android.util.Log
import android.util.TypedValue
import android.view.MotionEvent
import android.view.View
import java.io.IOException
import kotlin.math.*

// Jeu de billard 8. Tous les designs viennent de res/values/*.xml. */
class PoolView(ctx: Context, attrs: AttributeSet?) : View(ctx, attrs) {

    interface Listener {
        fun onHud(p0: String, p1: String, cur: Int, msg: String)
        fun onGameOver(winner: Int)
    }
    var listener: Listener? = null
    /** 0 = solo contre l’ordinateur, 1 = deux joueurs, 2 = en ligne */
    var mode = 1
    var myIdx = 0
    var ready = true
    /** niveau de l’ordinateur : 0 facile, 1 moyen, 2 difficile */
    var level = 1
    var onReplay: (() -> Unit)? = null
    var onHome: (() -> Unit)? = null
    private var overT = 0
    private class Conf(var x: Float, var y: Float, val vx: Float, val vy: Float, val c: Int, val s: Float, val ph: Float)
    private val conf = ArrayList<Conf>()
    var send: ((String) -> Unit)? = null
    private var shooter = 0
    private var aiWait = 0
    private var planned = false
    private var planA = 0f
    private var planP = 0f

    private class Ball(val id: Int, var x: Float, var y: Float, val color: Int) {
        var vx = 0f; var vy = 0f; var inP = false
        /** orientation 3D de la bille (matrice 3x3 par lignes) : sert à afficher les numéros qui tournent */
        val rot = floatArrayOf(1f, 0f, 0f, 0f, 1f, 0f, 0f, 0f, 1f)
    }
    private enum class St { AIM, MOVING, PLACE, OVER, STRIKE }

    // ---- design lu dans les ressources XML
    private fun fl(id: Int): Float { val tv = TypedValue(); resources.getValue(id, tv, true); return tv.float }
    private fun col(id: Int) = context.getColor(id)
    private fun num(id: Int) = resources.getInteger(id).toFloat()
    private fun str(id: Int) = context.getString(id)

    private val W = num(R.integer.table_width)
    private val H = num(R.integer.table_height)
    private val T = num(R.integer.frame)
    private val BR = num(R.integer.ball_radius)
    private val PR = num(R.integer.pocket_radius)
    private val STICK = num(R.integer.stick_length)
    private val FR = fl(R.dimen.friction)
    private val RE = fl(R.dimen.restitution)
    private val CU = fl(R.dimen.cushion_bounce)
    private val MP = fl(R.dimen.max_power)
    private val RD = fl(R.dimen.roll_decel)
    // geste de tir : on tire la queue en arrière avec le doigt (distance doigt - bille = puissance)
    private val PULL0 = 20f
    private val PULLMAX = 190f
    private var pullBase = PULL0

    private val L = T; private val RR = W - T; private val TP = T; private val B = H - T
    private val MX = (L + RR) / 2; private val MY = (TP + B) / 2
    private val pockets = listOf(
        floatArrayOf(L, TP), floatArrayOf(RR, TP), floatArrayOf(L, B), floatArrayOf(RR, B),
        floatArrayOf(MX, TP - 6), floatArrayOf(MX, B + 6)
    )

    // ---- état
    private val balls = ArrayList<Ball>()
    private lateinit var cue: Ball
    private var state = St.AIM
    private var cur = 0
    private val groups = IntArray(2)
    private var power = 0f; private var charging = false
    private var aim = 0f; private var mx = 0f; private var my = 0f
    private var firstHit = -1; private var cuePot = false; private var leftBefore = -1
    private val potted = ArrayList<Int>()
    private var msg = ""; private var winner = -1
    private var gameOverNotified = false
    private var sc = 1f; private var ox = 0f; private var oy = 0f

    private val p = Paint(Paint.ANTI_ALIAS_FLAG)
    private val tp = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
    private val tableBm: Bitmap by lazy { buildTable() }
    private val backgroundBm: Bitmap? by lazy {
        try {
            context.assets
                .open("flutter_assets/assets/images/background.png")
                .use { BitmapFactory.decodeStream(it) }
        } catch (error: IOException) {
            Log.e("PoolView", "Could not load Kadri game background", error)
            null
        }
    }
    private val backgroundPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
    private val backgroundShade = Paint(Paint.ANTI_ALIAS_FLAG).apply {
        color = 0x66000000
    }

    private fun groupOf(id: Int) = if (id in 1..7) 1 else if (id in 9..15) 2 else 0
    private fun name(i: Int) = when {
        mode == 0 -> if (i == 0) str(R.string.you) else str(R.string.computer) + " · " + resources.getStringArray(R.array.levels)[level.coerceIn(0, 2)]
        mode == 2 -> str(if (i == myIdx) R.string.you else R.string.opponent)
        else -> str(if (i == 0) R.string.p1 else R.string.p2)
    }
    private fun meIdx() = if (mode == 2) myIdx else 0
    private fun turnMsg() = when {
        mode == 0 && cur == 1 -> str(R.string.computer_turn)
        mode != 1 && cur == meIdx() -> str(R.string.your_turn)
        mode == 2 -> str(R.string.opponent_turn)
        else -> str(R.string.turn) + " " + name(cur)
    }
    private fun canControl() = ready && when (mode) { 0 -> cur == 0; 2 -> cur == myIdx; else -> true }
    private fun left(g: Int) = balls.count { !it.inP && groupOf(it.id) == g }
    private fun gName(g: Int) = str(if (g == 1) R.string.red else R.string.yellow)

    private fun mk(id: Int, x: Float, y: Float): Ball {
        val c = when {
            id == 0 -> col(R.color.ball_cue)
            id == 8 -> col(R.color.ball_eight)
            groupOf(id) == 1 -> col(R.color.ball_red)
            else -> col(R.color.ball_yellow)
        }
        val b0 = Ball(id, x, y, c)
        // orientation de départ au hasard, numéros bien visibles
        val ph = (Math.random() * 6.283).toFloat()
        roll(b0, cos(ph), sin(ph), (Math.random() * .7).toFloat())
        val tw = (Math.random() * 6.283).toFloat(); val c2 = cos(tw); val s2 = sin(tw)
        val r = b0.rot
        for (j in 0..2) { val x0 = r[j]; val y0 = r[3 + j]; r[j] = c2 * x0 - s2 * y0; r[3 + j] = s2 * x0 + c2 * y0 }
        return b0
    }

    fun newGame(seed: Long = System.nanoTime()) {
        balls.clear()
        cue = mk(0, L + .25f * (RR - L), MY); balls.add(cue)
        val ids = mutableListOf(1, 2, 3, 4, 5, 6, 7, 9, 10, 11, 12, 13, 14, 15); ids.shuffle(java.util.Random(seed))
        val d = 2 * BR + .6f; val ax = L + .68f * (RR - L)
        var k = 0; var n = 0
        for (r in 0..4) for (j in 0..r) {
            val id = if (k == 4) 8 else ids[n++]; k++
            balls.add(mk(id, ax + r * d * .866f, MY + (j - r / 2f) * d))
        }
        cur = 0; groups[0] = 0; groups[1] = 0; state = St.AIM; winner = -1
        gameOverNotified = false
        power = 0f; charging = false
        planned = false; aiWait = 0; msg = turnMsg(); hud()
        invalidate()
    }

    private fun hud() {
        fun card(i: Int): String {
            val g = groups[i]
            return name(i) + "\n" + if (g == 0) str(R.string.open_table) else gName(g) + " · " + left(g) + " " + str(R.string.left)
        }
        listener?.onHud(card(0), card(1), if (state == St.OVER) -1 else cur, msg)
        if (state == St.OVER && !gameOverNotified && winner >= 0) {
            gameOverNotified = true
            listener?.onGameOver(winner)
        }
    }

    // ---- physique
    private fun pot(b: Ball) { b.inP = true; b.vx = 0f; b.vy = 0f; if (b.id == 0) cuePot = true else potted.add(b.id) }

    private fun phys() {
        val s = 8
        repeat(s) {
            for (b in balls) {
                if (b.inP) continue
                b.x += b.vx / s; b.y += b.vy / s
                for (q in pockets) if (hypot(b.x - q[0], b.y - q[1]) < PR) { pot(b); break }
                if (b.inP) continue
                if (b.x < L + BR) { b.x = L + BR; b.vx = abs(b.vx) * CU }
                if (b.x > RR - BR) { b.x = RR - BR; b.vx = -abs(b.vx) * CU }
                if (b.y < TP + BR) { b.y = TP + BR; b.vy = abs(b.vy) * CU }
                if (b.y > B - BR) { b.y = B - BR; b.vy = -abs(b.vy) * CU }
            }
            for (i in balls.indices) for (j in i + 1 until balls.size) {
                val a = balls[i]; val b = balls[j]
                if (a.inP || b.inP) continue
                val dx = b.x - a.x; val dy = b.y - a.y; val dd = hypot(dx, dy)
                if (dd >= 2 * BR || dd == 0f) continue
                val nx = dx / dd; val ny = dy / dd; val ov = (2 * BR - dd) / 2
                a.x -= nx * ov; a.y -= ny * ov; b.x += nx * ov; b.y += ny * ov
                val dv = (a.vx - b.vx) * nx + (a.vy - b.vy) * ny
                if (dv > 0) {
                    val f = dv * (1 + RE) / 2
                    a.vx -= f * nx; a.vy -= f * ny; b.vx += f * nx; b.vy += f * ny
                    if (firstHit == -1) { if (a === cue) firstHit = b.id else if (b === cue) firstHit = a.id }
                }
            }
        }
        // frottement de roulement (constant + proportionnel) et rotation visible de la bille
        for (b in balls) {
            if (b.inP) continue
            val sp = hypot(b.vx, b.vy)
            if (sp <= 0f) continue
            val ns = sp * FR - RD
            if (ns < .05f) { b.vx = 0f; b.vy = 0f; continue }
            b.vx *= ns / sp; b.vy *= ns / sp
            roll(b, b.vx / ns, b.vy / ns, ns / BR)
        }
    }

    /** Fait rouler la bille : (dx,dy) = direction du déplacement, ang = angle en radians (distance / rayon). */
    private fun roll(b: Ball, dx: Float, dy: Float, ang: Float) {
        val ax = -dy; val ay = dx
        val cs = cos(ang); val sn = sin(ang); val t = 1f - cs
        val m00 = t * ax * ax + cs; val m01 = t * ax * ay; val m02 = ay * sn
        val m10 = t * ax * ay; val m11 = t * ay * ay + cs; val m12 = -ax * sn
        val m20 = -ay * sn; val m21 = ax * sn; val m22 = cs
        val r = b.rot
        for (j in 0..2) {
            val x = r[j]; val y = r[3 + j]; val z = r[6 + j]
            r[j] = m00 * x + m01 * y + m02 * z
            r[3 + j] = m10 * x + m11 * y + m12 * z
            r[6 + j] = m20 * x + m21 * y + m22 * z
        }
        var n = sqrt(r[0] * r[0] + r[3] * r[3] + r[6] * r[6]); r[0] /= n; r[3] /= n; r[6] /= n
        val d = r[1] * r[0] + r[4] * r[3] + r[7] * r[6]
        r[1] -= d * r[0]; r[4] -= d * r[3]; r[7] -= d * r[6]
        n = sqrt(r[1] * r[1] + r[4] * r[4] + r[7] * r[7]); r[1] /= n; r[4] /= n; r[7] /= n
        r[2] = r[3] * r[7] - r[6] * r[4]
        r[5] = r[6] * r[1] - r[0] * r[7]
        r[8] = r[0] * r[4] - r[3] * r[1]
    }

    private var strikeT = 0
    private var strikeN = 6
    private var strikePow = 0f
    private var strikeAim = 0f
    private var fade = 0

    /** Lance le coup : la queue est tirée en arrière puis frappe la bille blanche (animation), ensuite la bille part. */
    private fun shoot() {
        shooter = cur
        firstHit = -1; potted.clear(); cuePot = false
        leftBefore = if (groups[cur] == 0) -1 else left(groups[cur])
        strikePow = power; strikeAim = aim; strikeT = 0
        strikeN = (8 - 4 * power).toInt().coerceIn(4, 8)
        state = St.STRIKE
    }

    private fun launch() {
        val sp = strikePow * MP
        cue.vx = cos(strikeAim) * sp; cue.vy = sin(strikeAim) * sp
        fade = 16; state = St.MOVING
    }

    // ---- règles du billard 8
    private fun endTurn() {
        val me = cur; val op = 1 - me; val g = groups[me]
        var foul = false; var why = ""
        val need = if (g == 0) -1 else if (leftBefore == 0) 8 else g
        val fh = firstHit
        if (cuePot) { foul = true; why = str(R.string.f_cue) }
        else if (fh == -1) { foul = true; why = str(R.string.f_none) }
        else if (g != 0 && (if (fh == 8) 8 else groupOf(fh)) != need) { foul = true; why = str(R.string.f_wrong) }

        if (potted.contains(8)) {
            val win = !foul && g != 0 && leftBefore == 0
            winner = if (win) me else op; state = St.OVER
            msg = if (mode != 1 && winner == meIdx()) str(R.string.win_you) else "🏆 " + name(winner) + " " + str(R.string.win); hud(); return
        }
        if (g == 0 && !foul && potted.isNotEmpty()) { groups[me] = groupOf(potted[0]); groups[op] = 3 - groups[me] }
        val keep = !foul && potted.any { groupOf(it) == groups[me] }
        if (!keep) cur = op
        if (foul) {
            state = St.PLACE; cue.inP = false; cue.vx = 0f; cue.vy = 0f
            cue.x = L + .25f * (RR - L); cue.y = MY
            msg = "⚠ " + str(R.string.foul) + " : " + why + ". " + str(R.string.place)
        } else {
            state = St.AIM
            msg = if (keep) str(R.string.again) else turnMsg()
        }
        hud()
    }

    // ---- tactile : poser le doigt = viser, maintenir = charger, relâcher = tirer
    private fun okPlace() = balls.all { it === cue || it.inP || hypot(it.x - cue.x, it.y - cue.y) >= 2 * BR }

    override fun onTouchEvent(e: MotionEvent): Boolean {
        mx = (e.x - ox) / sc; my = (e.y - oy) / sc
        if (state == St.OVER) { if (e.actionMasked == MotionEvent.ACTION_UP) overTap(); return true }
        if (!canControl()) return true
        when (e.actionMasked) {
            MotionEvent.ACTION_DOWN -> if (state == St.AIM) { charging = true; power = 0f; pullBase = max(hypot(cue.x - mx, cue.y - my), PULL0) }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                if (charging) { charging = false; if (power > .06f) { if (mode == 2) send?.invoke("SHOT $aim $power"); shoot() }; power = 0f }
                else if (state == St.PLACE && okPlace()) { if (mode == 2) send?.invoke("PLACE ${cue.x} ${cue.y}"); state = St.AIM; msg = turnMsg(); hud() }
            }
        }
        return true
    }

    // ---- ordinateur (mode solo)
    private fun ai() {
        if (state == St.PLACE) {
            if (++aiWait < 45) return
            aiWait = 0
            for (i in 0..200) {
                cue.x = L + BR + Math.random().toFloat() * (RR - L - 2 * BR) * .45f
                cue.y = TP + BR + Math.random().toFloat() * (B - TP - 2 * BR)
                if (okPlace()) break
            }
            state = St.AIM; msg = turnMsg(); hud(); return
        }
        if (!planned) { if (++aiWait < intArrayOf(70, 50, 30)[level.coerceIn(0, 2)]) return; aiWait = 0; choose(); planned = true; power = 0f }
        aim = planA
        power += .03f
        if (power >= planP) { planned = false; shoot(); power = 0f }
    }

    private fun choose() {
        val g = groups[1]
        val targets = balls.filter {
            !it.inP && it.id != 0 && when { g == 0 -> it.id != 8; left(g) > 0 -> groupOf(it.id) == g; else -> it.id == 8 }
        }
        val cands = ArrayList<FloatArray>() // score, angle, puissance
        for (t in targets) for (k in pockets) {
            val tx = k[0] - t.x; val ty = k[1] - t.y; val td = hypot(tx, ty).coerceAtLeast(1f)
            val gx = t.x - tx / td * 2 * BR; val gy = t.y - ty / td * 2 * BR
            val cx = gx - cue.x; val cy = gy - cue.y; val cd = hypot(cx, cy).coerceAtLeast(1f)
            val cut = (cx * tx + cy * ty) / (cd * td)
            if (cut < .25f || !clear(cue.x, cue.y, gx, gy, t) || !clear(t.x, t.y, k[0], k[1], t)) continue
            cands.add(floatArrayOf(cut * 1000 / (cd + td), atan2(cy, cx), ((cd + td) * .018f + 4) / MP))
        }
        planA = atan2(MY - cue.y, MX - cue.x); planP = .6f
        if (cands.isNotEmpty()) {
            // facile : coup au hasard ; moyen et difficile : meilleur coup
            val c = if (level == 0) cands[(Math.random() * cands.size).toInt()] else cands.maxByOrNull { it[0] }!!
            planA = c[1]; planP = c[2]
        } else if (targets.isNotEmpty()) {
            val t = targets.minByOrNull { hypot(it.x - cue.x, it.y - cue.y) }!!
            planA = atan2(t.y - cue.y, t.x - cue.x); planP = .5f
        }
        val err = floatArrayOf(.14f, .05f, .012f)[level.coerceIn(0, 2)]
        planA += ((Math.random() - .5) * 2 * err).toFloat()
        if (level == 0 && Math.random() < .2) planA += ((Math.random() - .5) * 1.2).toFloat()
        planP = (planP * (if (level == 0) .7f + Math.random().toFloat() * .6f else 1f)).coerceIn(.25f, 1f)
    }

    private fun clear(x1: Float, y1: Float, x2: Float, y2: Float, ign: Ball): Boolean {
        val dx = x2 - x1; val dy = y2 - y1; val l2 = dx * dx + dy * dy
        if (l2 < 1f) return true
        for (b in balls) {
            if (b.inP || b === cue || b === ign) continue
            val u = (((b.x - x1) * dx + (b.y - y1) * dy) / l2).coerceIn(0f, 1f)
            if (hypot(b.x - (x1 + u * dx), b.y - (y1 + u * dy)) < 2 * BR - 1) return false
        }
        return true
    }

    // ---- en ligne : messages reçus de l’adversaire
    fun setMessage(m: String) { msg = m; hud() }
    fun remoteShot(a: Float, pw: Float) { if (state != St.AIM) return; aim = a; power = pw; shoot(); power = 0f }
    fun remotePlace(x: Float, y: Float) { if (state != St.PLACE) return; cue.x = x; cue.y = y; state = St.AIM; msg = turnMsg(); hud() }

    private fun snapshot() = "STATE " + cur + " " + groups[0] + " " + groups[1] + " " + state.ordinal + " " + winner + " " +
        balls.joinToString(",") { it.id.toString() + ":" + it.x + ":" + it.y + ":" + (if (it.inP) 1 else 0) }

    fun applySnapshot(line: String) {
        val f = line.split(" ")
        if (f.size < 7) return
        cur = f[1].toInt(); groups[0] = f[2].toInt(); groups[1] = f[3].toInt()
        state = St.values()[f[4].toInt()]; winner = f[5].toInt()
        for (sn in f[6].split(",")) {
            val q = sn.split(":")
            val b = balls.firstOrNull { it.id == q[0].toInt() } ?: continue
            b.x = q[1].toFloat(); b.y = q[2].toFloat(); b.inP = q[3] == "1"; b.vx = 0f; b.vy = 0f
        }
        power = 0f; charging = false
        msg = when (state) {
            St.OVER -> if (winner == myIdx) str(R.string.win_you) else "🏆 " + name(winner) + " " + str(R.string.win)
            St.PLACE -> str(R.string.foul) + " : " + str(R.string.place)
            else -> turnMsg()
        }
        hud()
    }

    // ---- animation de fin de partie
    private fun won() = if (mode == 1) true else winner == meIdx()

    private fun initConf() {
        conf.clear()
        if (!won()) return
        val cols = intArrayOf(0xFFFFD54A.toInt(), 0xFFE53935.toInt(), 0xFF42A5F5.toInt(), 0xFF66BB6A.toInt(), 0xFFFFFFFF.toInt(), 0xFFAB47BC.toInt())
        repeat(140) {
            conf.add(Conf(Math.random().toFloat() * W, -Math.random().toFloat() * H, (Math.random().toFloat() - .5f) * 1.2f,
                2f + Math.random().toFloat() * 3f, cols[(Math.random() * cols.size).toInt()],
                5f + Math.random().toFloat() * 7f, Math.random().toFloat() * 6.28f))
        }
    }

    private fun btn(c: Canvas, cx: Float, cy: Float, label: String, color: Int, a: Int) {
        p.shader = null; p.style = Paint.Style.FILL; p.color = color; p.alpha = a
        c.drawRoundRect(cx - 100, cy - 27, cx + 100, cy + 27, 27f, 27f, p)
        tp.textSize = 22f; tp.color = Color.WHITE; tp.alpha = a
        c.drawText(label, cx, cy + 8, tp)
    }

    private fun overTap() {
        if (overT < 40 || abs(my - (H - 110)) > 27) return
        if (abs(mx - (W / 2 - 115)) < 100) onReplay?.invoke()
        else if (abs(mx - (W / 2 + 115)) < 100) onHome?.invoke()
    }

    private fun drawOver(c: Canvas) {
        if (overT == 0) initConf()
        overT++
        val t = overT; val win = won()
        p.shader = null; p.style = Paint.Style.FILL
        p.color = if (win) Color.BLACK else 0xFF200000.toInt(); p.alpha = min(170, t * 7)
        c.drawRect(0f, 0f, W, H, p)
        // halo lumineux qui pulse
        val hc = if (win) 0xFFFFC107.toInt() else 0xFFE53935.toInt()
        p.shader = RadialGradient(W / 2, H / 2 - 40, 300f * (1f + .08f * sin(t * .09f)),
            (hc and 0x00FFFFFF) or 0x66000000, hc and 0x00FFFFFF, Shader.TileMode.CLAMP)
        p.alpha = 255; c.drawRect(0f, 0f, W, H, p); p.shader = null
        // confettis (victoire)
        for (q in conf) {
            q.y += q.vy; q.x += q.vx + sin(t * .05f + q.ph) * .8f
            if (q.y > H + 10) { q.y = -10f; q.x = Math.random().toFloat() * W }
            p.color = q.c; p.alpha = 255
            c.save(); c.translate(q.x, q.y); c.rotate((t * 4f + q.ph * 57f) % 360f)
            c.drawRect(-q.s / 2, -q.s / 4, q.s / 2, q.s / 4, p); c.restore()
        }
        // titre avec effet de rebond (et tremblement en cas de défaite)
        val k = min(1f, t / 28f); val u = k - 1f
        val ease = 1f + 2.70158f * u * u * u + 1.70158f * u * u
        val shake = if (!win && t < 30) sin(t * 1.4f) * (30 - t) * .6f else 0f
        val title = str(if (win) R.string.victory else R.string.defeat)
        c.save(); c.translate(W / 2 + shake, H / 2 - 40); c.scale(ease, ease)
        tp.textSize = 110f; tp.style = Paint.Style.STROKE; tp.strokeWidth = 12f; tp.color = 0xFF3A1F00.toInt(); tp.alpha = 255
        c.drawText(title, 0f, 20f, tp)
        tp.style = Paint.Style.FILL
        tp.shader = LinearGradient(0f, -70f, 0f, 40f, if (win) 0xFFFFF176.toInt() else 0xFFFF8A80.toInt(),
            if (win) 0xFFFF9800.toInt() else 0xFFC62828.toInt(), Shader.TileMode.CLAMP)
        c.drawText(title, 0f, 20f, tp); tp.shader = null
        tp.textSize = 80f; tp.color = Color.WHITE; c.drawText(if (win) "🏆" else "😔", 0f, -105f, tp)
        c.restore()
        if (t > 25) {
            val sub = if (mode == 1) name(winner) + " " + str(R.string.win) else str(if (win) R.string.win_sub else R.string.lose_sub)
            tp.textSize = 26f; tp.color = Color.WHITE; tp.alpha = min(255, (t - 25) * 12)
            c.drawText(sub, W / 2, H / 2 + 60, tp)
        }
        if (t > 40) {
            val a = min(255, (t - 40) * 12)
            btn(c, W / 2 - 115, H - 110, str(R.string.replay), col(R.color.accent), a)
            btn(c, W / 2 + 115, H - 110, str(R.string.home), col(R.color.rail_light), a)
        }
        tp.alpha = 255
    }

    // ---- dessin
    private fun buildTable(): Bitmap {
        val bm = Bitmap.createBitmap(W.toInt(), H.toInt(), Bitmap.Config.ARGB_8888)
        val c = Canvas(bm); val q = Paint(Paint.ANTI_ALIAS_FLAG)
        q.shader = LinearGradient(0f, 0f, 0f, H, intArrayOf(col(R.color.rail_light), col(R.color.rail_dark), col(R.color.rail_light)), null, Shader.TileMode.CLAMP)
        c.drawRoundRect(0f, 0f, W, H, 22f, 22f, q); q.shader = null
        q.style = Paint.Style.STROKE; q.strokeWidth = 4f; q.color = col(R.color.rail_edge)
        c.drawRoundRect(2f, 2f, W - 2, H - 2, 22f, 22f, q); q.style = Paint.Style.FILL
        q.color = col(R.color.cushion); c.drawRect(L - 10, TP - 10, RR + 10, B + 10, q)
        q.shader = RadialGradient(MX, MY, RR - L, col(R.color.felt_center), col(R.color.felt_edge), Shader.TileMode.CLAMP)
        c.drawRect(L, TP, RR, B, q); q.shader = null
        q.color = col(R.color.diamond)
        for (i in 1..7) if (i != 4) { val x = L + (RR - L) * i / 8; c.drawCircle(x, T / 2 - 5, 3.5f, q); c.drawCircle(x, H - T / 2 + 5, 3.5f, q) }
        for (i in 1..3) { val y = TP + (B - TP) * i / 4; c.drawCircle(T / 2 - 5, y, 3.5f, q); c.drawCircle(W - T / 2 + 5, y, 3.5f, q) }
        for (k in pockets) {
            q.color = col(R.color.pocket_ring); c.drawCircle(k[0], k[1], PR + 3, q)
            q.color = col(R.color.pocket); c.drawCircle(k[0], k[1], PR, q)
        }
        return bm
    }

    private val mtx = Matrix()
    private val clip = Path()

    private fun drawBall(c: Canvas, b: Ball, a: Int = 255) {
        if (b.inP) return
        val x = b.x; val y = b.y; val r = b.rot
        p.shader = null; p.style = Paint.Style.FILL
        p.color = Color.BLACK; p.alpha = 76 * a / 255
        c.drawOval(x + 3 - BR, y + 4 - BR * .8f, x + 3 + BR, y + 4 + BR * .8f, p)
        p.color = b.color; p.alpha = a; c.drawCircle(x, y, BR, p)
        c.save()
        clip.reset(); clip.addCircle(x, y, BR, Path.Direction.CW); c.clipPath(clip)
        if (b.id == 0) {
            // bille blanche : 6 points rouges pour voir la rotation
            p.color = 0xFFCC2222.toInt(); p.alpha = a
            for (k in 0..2) for (sg in intArrayOf(1, -1)) {
                val az = sg * r[6 + k]
                if (az > .05f) c.drawCircle(x + sg * r[k] * BR, y + sg * r[3 + k] * BR, BR * (.1f + .12f * az), p)
            }
        } else {
            // deux pastilles numérotées opposées, projetées sur la sphère qui tourne
            for (side in intArrayOf(1, -1)) {
                if (side * r[8] <= 0f) continue
                mtx.setValues(floatArrayOf(r[0], side * r[1], x + side * BR * r[2], r[3], side * r[4], y + side * BR * r[5], 0f, 0f, 1f))
                c.save(); c.concat(mtx)
                p.color = col(R.color.number_bg); p.alpha = a; c.drawCircle(0f, 0f, BR * .5f, p)
                tp.color = col(R.color.number_fg); tp.alpha = a; tp.textSize = BR * .7f
                c.drawText(b.id.toString(), 0f, BR * .25f, tp)
                c.restore()
            }
        }
        c.restore()
        // ombrage sphérique et reflet
        p.shader = RadialGradient(x - BR / 3, y - BR / 3, BR * 1.5f,
            intArrayOf(0xBFFFFFFF.toInt(), 0x00FFFFFF, 0x73000000), floatArrayOf(0f, .45f, 1f), Shader.TileMode.CLAMP)
        p.alpha = a; c.drawCircle(x, y, BR, p); p.shader = null
        p.color = Color.WHITE; p.alpha = 150 * a / 255
        c.drawOval(x - BR * .55f, y - BR * .62f, x - BR * .2f, y - BR * .3f, p)
    }

    private fun drawGuide(c: Canvas) {
        val dx = cos(aim); val dy = sin(aim)
        var t = 1e9f; var hit: Ball? = null
        for (b in balls) {
            if (b === cue || b.inP) continue
            val ox = b.x - cue.x; val oy = b.y - cue.y; val pr = ox * dx + oy * dy
            if (pr <= 0) continue
            val pp = abs(ox * dy - oy * dx)
            if (pp < 2 * BR) { val tt = pr - sqrt(4 * BR * BR - pp * pp); if (tt < t) { t = tt; hit = b } }
        }
        var tw = 1e9f
        if (dx > 0) tw = min(tw, (RR - BR - cue.x) / dx)
        if (dx < 0) tw = min(tw, (L + BR - cue.x) / dx)
        if (dy > 0) tw = min(tw, (B - BR - cue.y) / dy)
        if (dy < 0) tw = min(tw, (TP + BR - cue.y) / dy)
        if (hit == null || tw < t) { t = tw; hit = null }
        val ex = cue.x + dx * t; val ey = cue.y + dy * t
        p.shader = null; p.style = Paint.Style.STROKE; p.strokeWidth = 1.5f; p.color = col(R.color.guide)
        p.pathEffect = DashPathEffect(floatArrayOf(6f, 6f), 0f)
        c.drawLine(cue.x, cue.y, ex, ey, p); c.drawCircle(ex, ey, BR, p)
        if (hit != null) {
            val nx = hit.x - ex; val ny = hit.y - ey; val n = hypot(nx, ny).coerceAtLeast(.001f)
            c.drawLine(hit.x, hit.y, hit.x + nx / n * 45, hit.y + ny / n * 45, p)
        }
        p.pathEffect = null; p.style = Paint.Style.FILL; p.alpha = 255
    }

    private fun drawHandle(c: Canvas) {
        p.shader = null; p.style = Paint.Style.FILL; p.color = Color.WHITE; p.alpha = 60
        c.drawCircle(mx, my, 18f, p)
        p.style = Paint.Style.STROKE; p.strokeWidth = 2f; p.alpha = 170
        c.drawCircle(mx, my, 18f, p)
        p.style = Paint.Style.FILL; p.alpha = 255
    }

    private fun drawStick(c: Canvas, pull: Float = BR + 5 + power * 90, a: Int = 255) {
        c.save(); c.translate(cue.x, cue.y); c.rotate(Math.toDegrees(aim.toDouble()).toFloat())
        val path = Path().apply {
            moveTo(-pull, -2.2f); lineTo(-pull - STICK, -5.5f); lineTo(-pull - STICK, 5.5f); lineTo(-pull, 2.2f); close()
        }
        p.shader = null; p.color = Color.BLACK; p.alpha = 64 * a / 255
        c.save(); c.translate(3f, 3f); c.drawPath(path, p); c.restore()
        p.alpha = a
        p.shader = LinearGradient(-pull, 0f, -pull - STICK, 0f,
            intArrayOf(col(R.color.stick_shaft1), col(R.color.stick_shaft2), col(R.color.stick_butt), col(R.color.stick_butt)),
            floatArrayOf(0f, .62f, .63f, 1f), Shader.TileMode.CLAMP)
        c.drawPath(path, p); p.shader = null
        p.color = col(R.color.stick_tip); p.alpha = a; c.drawRect(-pull - 7, -2.4f, -pull, 2.4f, p)
        c.restore()
    }

    override fun onDraw(c: Canvas) {
        val inset = 18f * resources.displayMetrics.density
        val availableWidth = (width - 2 * inset).coerceAtLeast(0f)
        val availableHeight = (height - 2 * inset).coerceAtLeast(0f)
        sc = min(availableWidth / W, availableHeight / H)
        ox = (width - W * sc) / 2
        oy = (height - H * sc) / 2
        if (state == St.STRIKE) { strikeT++; if (strikeT >= strikeN) launch() }
        if (state == St.MOVING) {
            phys()
            if (balls.none { !it.inP && (it.vx != 0f || it.vy != 0f) }) { endTurn(); if (mode == 2 && shooter == myIdx) send?.invoke(snapshot()) }
        }
        if (mode == 0 && cur == 1 && (state == St.AIM || state == St.PLACE)) ai()
        else if (state == St.AIM && charging && canControl()) {
            val dx = cue.x - mx; val dy = cue.y - my; val d = hypot(dx, dy)
            if (d > 12f) aim = atan2(dy, dx)               // la queue pointe de la bille vers l’opposé du doigt
            pullBase = min(pullBase, max(d, PULL0))        // on peut revenir en avant puis tirer encore
            power = ((d - pullBase) / PULLMAX).coerceIn(0f, 1f)
        }
        if (state == St.PLACE && canControl()) { cue.x = mx.coerceIn(L + BR, RR - BR); cue.y = my.coerceIn(TP + BR, B - BR) }

        c.drawColor(col(R.color.hud_bg))
        backgroundBm?.let { background ->
            c.drawBitmap(
                background,
                null,
                Rect(0, 0, width, height),
                backgroundPaint
            )
            c.drawRect(0f, 0f, width.toFloat(), height.toFloat(), backgroundShade)
        }
        c.save(); c.translate(ox, oy); c.scale(sc, sc)
        c.drawBitmap(tableBm, 0f, 0f, null)
        for (b in balls) if (b !== cue) drawBall(c, b)
        drawBall(c, cue, if (state == St.PLACE && !okPlace()) 100 else 255)
        if (state == St.STRIKE) {
            // la queue accélère vers la bille blanche
            val k = strikeT.toFloat() / strikeN; val p0 = BR + 5 + strikePow * 90f
            drawStick(c, p0 + (BR + 1f - p0) * k * k)
        } else if (state == St.MOVING && fade > 0) {
            drawStick(c, BR + 1f - (16 - fade) * .2f, 255 * fade / 16); fade--
        }
        if (state == St.AIM) {
            if (canControl()) drawGuide(c)
            if (canControl() || mode == 0) drawStick(c)
            if (charging && canControl()) drawHandle(c)
            // barre de puissance sur le rebord du haut
            p.shader = null; p.color = col(R.color.rail_edge); c.drawRect(L, 5f, RR, 11f, p)
            p.color = col(R.color.accent); c.drawRect(L, 5f, L + (RR - L) * power, 11f, p)
        }
        if (state == St.OVER) drawOver(c) else overT = 0
        c.restore()
        postInvalidateOnAnimation()
    }
}
