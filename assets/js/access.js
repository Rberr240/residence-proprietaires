const accessForm = document.getElementById("accessForm");
const accessCodeInput = document.getElementById("accessCode");
const errorMessage = document.getElementById("errorMessage");

accessCodeInput.addEventListener("input", () => {

    let value = accessCodeInput.value;

    value = value.toUpperCase();

    value = value.replace(/\s+/g, "");

    accessCodeInput.value = value;

    errorMessage.textContent = "";
});


accessForm.addEventListener("submit", (event) => {

    event.preventDefault();

    const code = accessCodeInput.value.trim();

    if (code.length < 4) {

        errorMessage.textContent =
            "Veuillez entrer un code d'accès valide.";

        return;
    }

    /*
        Pour le moment, nous ne vérifions PAS
        réellement le code.

        La connexion à Supabase sera réalisée
        dans une étape suivante.
    */

    console.log("Code saisi :", code);

    errorMessage.textContent =
        "La vérification sécurisée sera activée prochainement.";
});