const ownerForm = document.getElementById("ownerForm");
const subject = document.getElementById("subject");
const characterCount = document.getElementById("characterCount");
const formMessage = document.getElementById("formMessage");
const apartmentNumber = document.getElementById("apartmentNumber");

const submitButton = ownerForm.querySelector(
  'button[type="submit"]',
);

const sessionToken = sessionStorage.getItem(
  "miradorRegistrationToken",
);

const apartmentRaw = sessionStorage.getItem(
  "miradorApartment",
);

const sessionExpiresAt = sessionStorage.getItem(
  "miradorSessionExpiresAt",
);

/*
 * ---------------------------------------------------------
 * Vérification de la session
 * ---------------------------------------------------------
 */

if (
  !sessionToken ||
  sessionToken.length !== 64 ||
  !apartmentRaw ||
  !sessionExpiresAt ||
  new Date(sessionExpiresAt).getTime() <= Date.now()
) {
  sessionStorage.removeItem("miradorRegistrationToken");
  sessionStorage.removeItem("miradorApartment");
  sessionStorage.removeItem("miradorSessionExpiresAt");

  window.location.replace("index.html");
}

/*
 * ---------------------------------------------------------
 * Affichage de l'appartement
 * ---------------------------------------------------------
 */

let apartment = null;

try {
  apartment = JSON.parse(apartmentRaw);
} catch {
  sessionStorage.clear();
  window.location.replace("index.html");
}

if (apartment && apartmentNumber) {
  apartmentNumber.textContent =
    `${apartment.buildingName} — ${apartment.number}`;
}

/*
 * ---------------------------------------------------------
 * Compteur du sujet
 * ---------------------------------------------------------
 */

if (subject && characterCount) {
  characterCount.textContent = subject.value.length;

  subject.addEventListener("input", () => {
    characterCount.textContent = subject.value.length;
  });
}

/*
 * ---------------------------------------------------------
 * Enregistrement propriétaire
 * ---------------------------------------------------------
 */

ownerForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  formMessage.textContent = "";

  const firstName = document
    .getElementById("firstName")
    .value
    .trim();

  const lastName = document
    .getElementById("lastName")
    .value
    .trim();

  const phone = document
    .getElementById("phone")
    .value
    .trim();

  const whatsapp = document
    .getElementById("whatsapp")
    .value
    .trim();

  const email = document
    .getElementById("email")
    .value
    .trim();

  const consent = document
    .getElementById("consent")
    .checked;

  if (!firstName || !lastName || !phone) {
    formMessage.textContent =
      "Veuillez remplir les champs obligatoires.";
    return;
  }

  if (!consent) {
    formMessage.textContent =
      "Vous devez accepter l'utilisation de vos coordonnées.";
    return;
  }

  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Enregistrement...";
  }

  try {
    const response = await fetch(
      `${FUNCTIONS_URL}/submit-registration`,
      {
        method: "POST",

        headers: {
          apikey: SUPABASE_PUBLISHABLE_KEY,
          "Content-Type": "application/json",
        },

        body: JSON.stringify({
          sessionToken,
          firstName,
          lastName,
          phone,
          whatsapp,
          email,
          consent,
        }),
      },
    );

    let result;

    try {
      result = await response.json();
    } catch {
      throw new Error("Réponse serveur invalide.");
    }

    if (!response.ok || !result.success) {
      formMessage.textContent =
        result.message ||
        "Impossible d'enregistrer vos informations.";

      return;
    }

    /*
     * Le token a été consommé côté serveur.
     * On le supprime également du navigateur.
     */

    sessionStorage.removeItem(
      "miradorRegistrationToken",
    );

    sessionStorage.removeItem(
      "miradorApartment",
    );

    sessionStorage.removeItem(
      "miradorSessionExpiresAt",
    );

    window.location.replace("confirmation.html");
  } catch (error) {
    console.error(
      "Owner registration failed:",
      error,
    );

    formMessage.textContent =
      "Une erreur est survenue. Veuillez réessayer.";
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent =
        "Enregistrer mes informations →";
    }
  }
});