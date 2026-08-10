const accessForm = document.getElementById("accessForm");
const accessCodeInput = document.getElementById("accessCode");
const errorMessage = document.getElementById("errorMessage");
const submitButton = accessForm.querySelector('button[type="submit"]');

accessCodeInput.addEventListener("input", () => {
  let value = accessCodeInput.value;

  value = value.toUpperCase();
  value = value.replace(/\s+/g, "");

  accessCodeInput.value = value;
  errorMessage.textContent = "";
});

accessForm.addEventListener("submit", async (event) => {
  event.preventDefault();

  const code = accessCodeInput.value.trim();

  if (!/^[A-Z0-9-]{8,32}$/.test(code)) {
    errorMessage.textContent =
      "Veuillez entrer un code d'accès valide.";
    return;
  }

  errorMessage.textContent = "";

  if (submitButton) {
    submitButton.disabled = true;
    submitButton.textContent = "Vérification...";
  }

  try {
    const response = await fetch(
      `${FUNCTIONS_URL}/validate-access-code`,
      {
        method: "POST",
        headers: {
          apikey: SUPABASE_PUBLISHABLE_KEY,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          code,
        }),
      },
    );

    const result = await response.json();

    if (!response.ok || !result.valid) {
      errorMessage.textContent =
        result.message ||
        "Code d'accès invalide ou indisponible.";
      return;
    }

    if (
      typeof result.sessionToken !== "string" ||
      result.sessionToken.length !== 64
    ) {
      throw new Error("Invalid registration session.");
    }

    sessionStorage.setItem(
      "miradorRegistrationToken",
      result.sessionToken,
    );

    sessionStorage.setItem(
      "miradorApartment",
      JSON.stringify(result.apartment),
    );

    sessionStorage.setItem(
      "miradorSessionExpiresAt",
      result.expiresAt,
    );

    window.location.href = "inscription.html";
  } catch (error) {
    console.error("Access validation failed:", error);

    errorMessage.textContent =
      "Impossible de vérifier le code pour le moment. Veuillez réessayer.";
  } finally {
    if (submitButton) {
      submitButton.disabled = false;
      submitButton.textContent = "Continuer";
    }
  }
});