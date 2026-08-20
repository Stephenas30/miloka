import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const RESEND_API_KEY = Deno.env.get('RESEND_API_KEY')
const FROM_EMAIL = 'feedback@smartdev-solutions.com'
const TO_EMAIL = 'contact@smartdev-solutions.com'

serve(async (req) => {
  try {
    const { category, message, contact_email, user_id } = await req.json()

    const subject = `[Kadri Feedback] ${category} - ${contact_email || 'anonyme'}`
    const html = `
      <h2>Nouveau feedback Kadri</h2>
      <p><strong>Catégorie :</strong> ${category}</p>
      <p><strong>Email de contact :</strong> ${contact_email || 'Non renseigné'}</p>
      <p><strong>Utilisateur ID :</strong> ${user_id || 'Non connecté'}</p>
      <hr/>
      <p><strong>Message :</strong></p>
      <p>${message.replace(/\n/g, '<br/>')}</p>
    `

    if (!RESEND_API_KEY) {
      return new Response(JSON.stringify({ error: 'RESEND_API_KEY not configured' }), { status: 500 })
    }

    const res = await fetch('https://api.resend.com/emails', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${RESEND_API_KEY}`,
      },
      body: JSON.stringify({
        from: FROM_EMAIL,
        to: TO_EMAIL,
        subject,
        html,
      }),
    })

    if (!res.ok) {
      const err = await res.text()
      return new Response(JSON.stringify({ error: err }), { status: 500 })
    }

    return new Response(JSON.stringify({ success: true }), { status: 200 })
  } catch (e) {
    return new Response(JSON.stringify({ error: e.message }), { status: 500 })
  }
})
